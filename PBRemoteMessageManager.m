//
//  PBRemoteMessageManager.m
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessageManager.h"
#import "PBRemoteMessage.h"
#import "PBRemoteMessagingClient.h"
#import "PBRemoteNotificationMessage.h"
#import "Reachability.h"
#import "GCDAsyncSocket.h"
#import "PBRemoteClientInfo.h"
#import "DDLog.h"
#import "NSString+GUID.h"

#define READ_TIMEOUT 15.0

NSString * const kPBRemoteMessageIDKey = @"message-id";
NSString * const kPBRemotePayloadKey = @"payload";
NSString * const kPBRemoteMessageManagerActiveNotification =
@"kPBRemoteMessageManagerActiveNotification";
NSString * const kPBRemoteMessageManagerInactiveNotification =
@"kPBRemoteMessageManagerInactiveNotification";
NSString * const kPBPingNotification = @"kPBPingNotification";
NSString * const kPBPongNotification = @"kPBPongNotification";

@interface PBRemoteMessageManager()
<NSNetServiceBrowserDelegate, NSNetServiceDelegate, PBRemoteMessagingClientDelegate>  {

    dispatch_queue_t _socketQueue;
}

@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) GCDAsyncSocket *listenSocket;
@property (nonatomic, strong) NSMutableArray *connectedSockets;

@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) NSString *serviceType;
@property (nonatomic, strong) NSString *serviceName;

@property (nonatomic, strong) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, strong) NSMutableDictionary *clients;

@end

@implementation PBRemoteMessageManager

- (id)init {
    self = [super init];

    if (self != nil) {

        self.clients = [NSMutableDictionary dictionary];

        _maxClients = -1.0f;

        _socketQueue = dispatch_queue_create("socketQueue", NULL);

        self.listenSocket =
        [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];

        self.connectedSockets = [NSMutableArray array];

#if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(applicationDidEnterBackground:)
         name:UIApplicationDidEnterBackgroundNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(applicationWillEnterForeground:)
         name:UIApplicationWillEnterForegroundNotification
         object:nil];
#endif

    }

    return self;
}

- (void)dealloc {
}

- (NSString *)serviceType {
    if (_serviceType == nil) {
        self.serviceType =
        [NSString stringWithFormat:@"_%@._tcp.", _serviceName];
    }
    return _serviceType;
}

- (void)startWithServiceName:(NSString *)serviceName {

    if (_netService == nil) {

        self.serviceName = serviceName;

        [self doStart];
    }
}

- (void)restartServiceBrowser {
    [_netServiceBrowser stop];
    [_netServiceBrowser
     searchForServicesOfType:[PBRemoteMessageManager sharedInstance].serviceType
     inDomain:@"local."];
}

- (void)doStart {

    if (_netService == nil) {

        NSError *err = nil;
        if ([_listenSocket acceptOnPort:0 error:&err]) {

            [_netServiceBrowser stop];
            self.netServiceBrowser = [[NSNetServiceBrowser alloc] init];

            [_netServiceBrowser setDelegate:self];
            [_netServiceBrowser
             searchForServicesOfType:[PBRemoteMessageManager sharedInstance].serviceType
             inDomain:@"local."];

            // So what port did the OS give us?

            UInt16 port = [_listenSocket localPort];

            self.netService =
            [[NSNetService alloc]
             initWithDomain:@"local."
             type:self.serviceType
             name:[NSString deviceIdentifier]
             port:port];

            NSLog(@"creating net service: %@", _netService);

            [_netService setDelegate:self];
            [_netService publish];

            //		// You can optionally add TXT record stuff
            //
            //		NSMutableDictionary *txtDict = [NSMutableDictionary dictionaryWithCapacity:2];
            //
            //		[txtDict setObject:@"moo" forKey:@"cow"];
            //		[txtDict setObject:@"quack" forKey:@"duck"];
            //
            //		NSData *txtData = [NSNetService dataFromTXTRecordDictionary:txtDict];
            //		[netService setTXTRecordData:txtData];

            [[NSNotificationCenter defaultCenter]
             addObserver:self
             selector:@selector(handleNetworkChange:)
             name:kReachabilityChangedNotification
             object:nil];

            [[NSNotificationCenter defaultCenter]
             addObserver:self
             selector:@selector(handlePing:)
             name:kPBPingNotification
             object:nil];

            self.reachability = [Reachability reachabilityForInternetConnection];
            [self.reachability startNotifier];
            
        } else {
            NSLog(@"Error in acceptOnPort:error: -> %@", err);
        }
    }
}

- (void)cleanupClient:(PBRemoteClientInfo *)clientInfo {
    [clientInfo.client stop];
    clientInfo.client = nil;
    clientInfo.netService = nil;
}

- (void)stop {

    if (_netService != nil) {

        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:kReachabilityChangedNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:kPBPingNotification
         object:nil];

        [_listenSocket disconnect];

        [_netService stop];

        for (PBRemoteClientInfo *clientInfo in _clients.allValues) {
            [self cleanupClient:clientInfo];
        }

        [_clients removeAllObjects];

        @synchronized (_connectedSockets) {
            for (GCDAsyncSocket *socket in _connectedSockets) {
                [socket disconnect];
            }
        }

        [_connectedSockets removeAllObjects];

        self.netService = nil;

        [[NSNotificationCenter defaultCenter]
         postNotificationName:kPBRemoteMessageManagerInactiveNotification
         object:self
         userInfo:nil];

        [_netServiceBrowser stop];

        self.netServiceBrowser = nil;
    }
}

- (NSTimeInterval)averageClientRoundTripTime {
    NSTimeInterval avgTime = 0.0f;

    NSInteger count = 0;

    for (PBRemoteClientInfo *clientInfo in _clients.allValues) {
        avgTime += clientInfo.client.averageRoundTripTime;
        count++;
    }

    return avgTime / (NSTimeInterval)count;
}

- (void)handlePing:(NSNotificationCenter *)notification {
    [PBRemoteNotificationMessage
     sendNotification:kPBPongNotification];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    [self stop];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    [self doStart];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
	// This method is executed on the socketQueue (not the main thread)

    BOOL socketAdded = NO;

	@synchronized(_connectedSockets) {
        if (_maxClients < 0.0f || _connectedSockets.count < _maxClients) {
            [_connectedSockets addObject:newSocket];
            socketAdded = YES;
        }
	}

    if (socketAdded) {
        [[NSNotificationCenter defaultCenter]
         postNotificationName:kPBRemoteMessageManagerActiveNotification
         object:self
         userInfo:nil];
    } else {
        [newSocket disconnect];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	if (sock != _listenSocket) {
        NSLog(@"Client Disconnected");

		@synchronized(_connectedSockets) {
			[_connectedSockets removeObject:sock];
		}
	}
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
	return 0.0;
}

#pragma mark - Instance methods

- (void)sendBroadcastMessage:(PBRemoteMessage *)message {

    for (GCDAsyncSocket *socket in _connectedSockets) {
        [self sendMessage:message socket:socket];
    }
}

- (void)sendMessage:(PBRemoteMessage *)message socket:(GCDAsyncSocket *)socket {

    PBRemoteNotificationMessage *noti = (id)message;

    if ([noti isKindOfClass:[PBRemoteNotificationMessage class]]) {
//        NSLog(@"sending %@...", noti.notificationName);
    }
    
    NSDictionary *fullMessage =
    @{
    kPBRemoteMessageIDKey : message.messageID,
    kPBRemotePayloadKey : message.payload,
    };

    NSData *packet =
    [NSPropertyListSerialization
     dataFromPropertyList:fullMessage
     format:NSPropertyListBinaryFormat_v1_0
     errorDescription:NULL];

    @synchronized (self) {

        static NSData *preambleData = nil;

        if (preambleData == nil) {
            preambleData = [PBRemoteMessage.messagePreamble dataUsingEncoding:NSUTF8StringEncoding];
        }

        uint32_t length = (uint32_t)packet.length;
        NSData *lengthData = [NSData dataWithBytes:&length length:sizeof(length)];

        [socket writeData:preambleData withTimeout:-1.0f tag:0];
        [socket writeData:lengthData withTimeout:-1.0f tag:0];
        [socket writeData:packet withTimeout:-1.0f tag:0];
//        [socket writeData:[GCDAsyncSocket CRLFData] withTimeout:-1.0f tag:0];
    }
}

- (PBRemoteClientInfo *)clientInfoForService:(NSNetService *)netService {
    return [_clients objectForKey:netService.name];
}

- (PBRemoteClientInfo *)clientInfoForClient:(PBRemoteMessagingClient *)client {

    for (PBRemoteClientInfo *clientInfo in _clients.allValues) {
        if (clientInfo.client == client) {
            return clientInfo;
        }
    }

    return nil;
}

#pragma mark - NSNetBrowserDelegate Conformance

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender didNotSearch:(NSDictionary *)errorInfo {
	NSLog(@"DidNotSearch: %@", errorInfo);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
           didFindService:(NSNetService *)netService
               moreComing:(BOOL)moreServicesComing {

    if ([netService.name isEqualToString:[NSString deviceIdentifier]] == NO) {

        NSLog(@"DidFindService: %@", [netService name]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        if (clientInfo != nil) {
            [self cleanupClient:clientInfo];
        } else {
            if (_maxClients < 0 || _maxClients < _clients.count) {
                clientInfo = [[PBRemoteClientInfo alloc] init];
                [_clients setObject:clientInfo forKey:netService.name];
            }
        }

        clientInfo.netService = netService;
        netService.delegate = self;
        [netService resolveWithTimeout:5.0f];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
         didRemoveService:(NSNetService *)netService
               moreComing:(BOOL)moreServicesComing {

    if ([netService.name isEqualToString:[NSString deviceIdentifier]] == NO) {

        NSLog(@"DidRemoveService: %@", [netService name]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        [clientInfo.client stop];

        [_clients removeObjectForKey:netService.name];

        if (_clients.count == 0) {
            [[NSNotificationCenter defaultCenter]
             postNotificationName:kPBRemoteMessageManagerInactiveNotification
             object:self
             userInfo:nil];
        }
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)sender {
	NSLog(@"DidStopSearch");
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
	NSLog(@"DidNotResolve");
}

- (void)netServiceDidResolveAddress:(NSNetService *)netService {

    if ([netService.name isEqualToString:[NSString deviceIdentifier]] == NO) {

        NSLog(@"DidResolve: %@ - %@", netService, [netService addresses]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        if (clientInfo != nil) {
            [self cleanupClient:clientInfo];
        } else {

            if (_maxClients < 0 || _maxClients < _clients.count) {
                clientInfo = [[PBRemoteClientInfo alloc] init];
                [_clients setObject:clientInfo forKey:netService.name];
            }
        }

        clientInfo.client = [[PBRemoteMessagingClient alloc] init];
        clientInfo.client.delegate = self;
        
        clientInfo.client.serverAddresses = [[netService addresses] mutableCopy];
        [clientInfo.client start];
    }
}

#pragma mark - PBRemoteMessagingClientDelegate Conformance

- (void)clientDisconnected:(PBRemoteMessagingClient *)client {

    PBRemoteClientInfo *clientInfo =
    [self clientInfoForClient:client];

    if (clientInfo != nil) {

        __block NSString *keyToRemove = nil;

        [_clients enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            PBRemoteClientInfo *ci = obj;
            if (ci.client == client) {
                keyToRemove = key;
                *stop = YES;
            }
        }];

        if (keyToRemove != nil) {
            [_clients removeObjectForKey:keyToRemove];
        }
        
        [self cleanupClient:clientInfo];
    }

    [self restartServiceBrowser];
}

#pragma mark - Reachability
- (void)handleNetworkChange:(NSNotification *)notice {
    NetworkStatus status = [self.reachability currentReachabilityStatus];

    NetworkStatus startStatus;

#if TARGET_OS_IPHONE
    startStatus = kReachableViaWWAN;
#else
    startStatus = ReachableViaWWAN;
#endif

    //handle change in network
    if (status == startStatus) {
        [self stop];
        [self doStart];
    }
}

- (BOOL)isWifiAvailable {
    NetworkStatus wifiStatus;

#if TARGET_OS_IPHONE
    wifiStatus = kReachableViaWiFi;
#else
    wifiStatus = ReachableViaWiFi;
#endif

    return (self.reachability.currentReachabilityStatus == wifiStatus);
}

#pragma mark - Singleton Methods

static dispatch_once_t predicate_;
static PBRemoteMessageManager *sharedInstance_ = nil;

+ (id)sharedInstance {
    
    dispatch_once(&predicate_, ^{
        sharedInstance_ = [PBRemoteMessageManager alloc];
        sharedInstance_ = [sharedInstance_ init];
    });
    
    return sharedInstance_;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
