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
#import "NSString+GUID.h"
#import "PBUserIdentity.h"

#define READ_TIMEOUT 15.0

NSString * const kPBRemoteMessageIDKey = @"message-id";
NSString * const kPBRemotePayloadKey = @"payload";
NSString * const kPBRemoteMessageManagerActiveNotification =
@"kPBRemoteMessageManagerActiveNotification";
NSString * const kPBRemoteMessageManagerInactiveNotification =
@"kPBRemoteMessageManagerInactiveNotification";
NSString * const kPBPingNotification = @"kPBPingNotification";
NSString * const kPBPongNotification = @"kPBPongNotification";
NSString * const kPBUserIdentityDeviceIDKey = @"userIdentity-deviceID";
NSString * const kPBUserIdentityUsernameKey = @"userIdentity-username";
NSString * const kPBUserIdentityFullNameKey = @"userIdentity-fullName";
NSString * const kPBUserIdentityEmailKey = @"userIdentity-email";

@interface PBRemoteMessageManager()
<NSNetServiceBrowserDelegate, NSNetServiceDelegate, PBRemoteMessagingClientDelegate>  {

    dispatch_queue_t _socketQueue;
    BOOL _starting;
}

@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) GCDAsyncSocket *listenSocket;
@property (nonatomic, strong) NSMutableArray *connectedSockets;

@property (nonatomic, readwrite) Reachability *reachability;
@property (nonatomic, strong) NSString *serviceName;

@property (nonatomic, strong) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, strong) NSMutableDictionary *clients;

@property (nonatomic, strong) NSMutableSet *registeredDevices;
@property (nonatomic, strong) NSManagedObjectID *userIdentityObjectID;

@property (nonatomic, strong) NSMutableDictionary *connectedIdentities;

@end

@implementation PBRemoteMessageManager

- (id)init {
    self = [super init];

    if (self != nil) {

        self.clients = [NSMutableDictionary dictionary];
        self.registeredDevices = [NSMutableSet set];
        self.connectedIdentities = [NSMutableDictionary dictionary];

        _maxClients = -1.0f;

        _socketQueue = dispatch_queue_create("socketQueue", NULL);

        self.listenSocket =
        [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];

        self.connectedSockets = [NSMutableArray array];

        self.reachability = [Reachability reachabilityForInternetConnection];
        [self.reachability startNotifier];

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

- (BOOL)hasConnections {
    return _clients.count > 0;
}

- (void)registeredDevice:(NSString *)deviceIdentifier {
    [_registeredDevices addObject:deviceIdentifier];
    [self restartServiceBrowser];
}

- (void)unregisterDevice:(NSString *)deviceIdentifier {
    [_registeredDevices removeObject:deviceIdentifier];
}

- (NSString *)serviceType {
    return [NSString stringWithFormat:@"_%@._tcp.", _serviceName];
}

- (void)startWithServiceName:(NSString *)serviceName {

    if (_netService == nil) {

        if ([_delegate respondsToSelector:@selector(userIdentity:fullName:email:)]) {

            NSString *username = nil;
            NSString *fullName = nil;
            NSString *email = nil;

            [_delegate
             userIdentity:&username
             fullName:&fullName
             email:&email];

            if (username.length > 0) {

                PBUserIdentity *userIdentity =
                [PBUserIdentity userIdentityWithUsername:username];

                if (userIdentity == nil) {
                    userIdentity =
                    [PBUserIdentity
                     createUserIdentityWithUsername:username
                     fullName:fullName
                     email:email];
                } else {
                    userIdentity.fullName = fullName;
                    userIdentity.email = email;
                }

                [userIdentity save];
                self.userIdentityObjectID = userIdentity.objectID;
            }
        }

        self.serviceName = serviceName;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self doStart];
        });
    }
}

- (PBUserIdentity *)userIdentity {
    return [PBUserIdentity userIdentityWithID:_userIdentityObjectID];
}

- (void)restartServiceBrowser {
    [_netServiceBrowser stop];
    [_netServiceBrowser
     searchForServicesOfType:[PBRemoteMessageManager sharedInstance].serviceType
     inDomain:@"local."];
}
- (void)doStart {

    if (_netService == nil && _starting == NO) {

        _starting = YES;

        if (_deviceIdentifier == nil) {
            self.deviceIdentifier = [NSString deviceIdentifier];
        }

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
             name:self.deviceIdentifier
             port:port];

            NSLog(@"creating net service: %@", _netService);

            [_netService setDelegate:self];
            [_netService publish];

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
            
        } else {
            NSLog(@"Error in acceptOnPort:error: -> %@", err);
        }

        _starting = NO;
    }
}

- (void)cleanupClient:(PBRemoteClientInfo *)clientInfo {
    [clientInfo.client stop];
    clientInfo.client = nil;
    clientInfo.netService = nil;
}

- (BOOL)isConnectedToClient:(NSString *)clientIdentifier {
    return [_clients objectForKey:clientIdentifier] != nil;
}

- (NSArray *)connectedIdentities {

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:_connectedIdentities.count];

    for (NSManagedObjectID *objectID in _connectedIdentities.allValues) {

        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithID:objectID];

        if (userIdentity != nil) {
            [result addObject:userIdentity];
        }
    }

    return result;
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
        [_connectedIdentities removeAllObjects];

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

- (void)handlePing:(NSNotification *)notification {

    NSString *clientID =
    [notification.userInfo objectForKey:kPBUserIdentityDeviceIDKey];
    NSString *username =
    [notification.userInfo objectForKey:kPBUserIdentityUsernameKey];
    NSString *fullName =
    [notification.userInfo objectForKey:kPBUserIdentityFullNameKey];
    NSString *email =
    [notification.userInfo objectForKey:kPBUserIdentityEmailKey];

    if (username.length > 0) {
        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithUsername:username];

        if (userIdentity == nil) {
            userIdentity =
            [PBUserIdentity
             createUserIdentityWithUsername:username
             fullName:fullName
             email:email];
        } else {
            userIdentity.fullName = fullName;
            userIdentity.email = email;
        }

        [userIdentity save];

        [_connectedIdentities setObject:userIdentity.objectID forKey:clientID];

        if ([_delegate respondsToSelector:@selector(userIdentityConnected:)]) {
            [_delegate userIdentityConnected:userIdentity];
        }
    }

    [PBRemoteNotificationMessage
     sendNotification:kPBPongNotification
     userInfo:notification.userInfo];
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

        [sock disconnect];
        
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

- (void)sendMessage:(PBRemoteMessage *)message {

    for (GCDAsyncSocket *socket in _connectedSockets) {
        [self sendMessage:message raw:NO socket:socket];
    }
}

- (void)sendRawMessage:(PBRemoteMessage *)message {

    for (GCDAsyncSocket *socket in _connectedSockets) {
        [self sendMessage:message raw:YES socket:socket];
    }
}

- (void)sendMessage:(PBRemoteMessage *)message raw:(BOOL)raw socket:(GCDAsyncSocket *)socket {

    NSData *packet;

    if (message.rawData != nil) {
        packet = message.rawData;
    } else {
        NSDictionary *fullMessage =
        @{
        kPBRemoteMessageIDKey : message.messageID,
        kPBRemotePayloadKey : message.payload,
        };

        packet =
        [NSPropertyListSerialization
         dataFromPropertyList:fullMessage
         format:NSPropertyListBinaryFormat_v1_0
         errorDescription:NULL];
    }

    @synchronized (self) {

        NSData *preamble = raw ? PBRemoteMessage.rawMessagePreamble : PBRemoteMessage.messagePreamble;

        uint32_t length = (uint32_t)packet.length;
        NSData *lengthData = [NSData dataWithBytes:&length length:sizeof(length)];

        [socket writeData:preamble withTimeout:-1.0f tag:0];
        [socket writeData:lengthData withTimeout:-1.0f tag:0];
        [socket writeData:packet withTimeout:-1.0f tag:0];
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

    if ([netService.name isEqualToString:self.deviceIdentifier] == NO) {

        NSLog(@"DidFindService: %@", [netService name]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        if (clientInfo != nil) {
            [self cleanupClient:clientInfo];
        } else {
            if (_maxClients < 0 || _maxClients < _clients.count) {
                if (_onlyConnectToRegisteredDevices == NO ||
                    [_registeredDevices containsObject:netService.name]) {
                    clientInfo = [[PBRemoteClientInfo alloc] init];
                    [_clients setObject:clientInfo forKey:netService.name];
                }
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

    if ([netService.name isEqualToString:self.deviceIdentifier] == NO) {

        NSLog(@"DidRemoveService: %@", [netService name]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        [clientInfo.client stop];

        [_clients removeObjectForKey:netService.name];

        if ([_delegate respondsToSelector:@selector(userIdentityDisconnected:)]) {

            NSManagedObjectID *objectID = [_connectedIdentities objectForKey:netService.name];

            PBUserIdentity *userIdentity =
            [PBUserIdentity userIdentityWithID:objectID];

            if (userIdentity != nil) {
                [_delegate userIdentityDisconnected:userIdentity];
            }
        }

        [_connectedIdentities removeObjectForKey:netService.name];
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)sender {
	NSLog(@"DidStopSearch");
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
	NSLog(@"DidNotResolve");
}

- (void)netServiceDidResolveAddress:(NSNetService *)netService {

    if ([netService.name isEqualToString:self.deviceIdentifier] == NO) {

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
        clientInfo.client.globalDelegate = _delegate;
        
        clientInfo.client.serverAddresses = [[netService addresses] mutableCopy];
        [clientInfo.client start];
    }
}

#pragma mark - PBRemoteMessagingClientDelegate Conformance

- (void)clientConnected:(PBRemoteMessagingClient *)client {

    if ([_delegate respondsToSelector:@selector(clientConnected:)]) {

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForClient:client];

        if (clientInfo.netService.name.length > 0) {
            [_delegate clientConnected:clientInfo.netService.name];
        }
    }
}

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

            if ([_delegate respondsToSelector:@selector(userIdentityDisconnected:)]) {

                NSManagedObjectID *objectID = [_connectedIdentities objectForKey:keyToRemove];

                PBUserIdentity *userIdentity =
                [PBUserIdentity userIdentityWithID:objectID];

                if (userIdentity != nil) {
                    [_delegate userIdentityDisconnected:userIdentity];
                }
            }

            [_connectedIdentities removeObjectForKey:keyToRemove];
        }
        
        [self cleanupClient:clientInfo];

        if ([_delegate respondsToSelector:@selector(clientConnected:)]) {

            if (clientInfo.netService.name.length > 0) {
                [_delegate clientDisconnected:clientInfo.netService.name];
            }
        }
    }

    [self restartServiceBrowser];

    if (_clients.count == 0) {
        [[NSNotificationCenter defaultCenter]
         postNotificationName:kPBRemoteMessageManagerInactiveNotification
         object:self
         userInfo:nil];
    }
}

#pragma mark - Reachability
- (void)handleNetworkChange:(NSNotification *)notice {
    NetworkStatus status = [self.reachability currentReachabilityStatus];

    //handle change in network
    if (status == ReachableViaWWAN) {
        [self stop];
        [self doStart];
    }
}

- (BOOL)isWifiAvailable {
    return (self.reachability.currentReachabilityStatus == ReachableViaWiFi);
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
