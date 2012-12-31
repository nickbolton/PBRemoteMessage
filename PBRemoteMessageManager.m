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
#import "NSString+Utilities.h"
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
NSString * const kPBClientIdentityRequestNotification = @"kPBClientIdentityRequestNotification";
NSString * const kPBClientIdentityResponseNotification = @"kPBClientIdentityResponseNotification";
NSString * const kPBUserIdentityUsernameKey = @"userIdentity-username";
NSString * const kPBUserIdentityFullNameKey = @"userIdentity-fullName";
NSString * const kPBUserIdentityEmailKey = @"userIdentity-email";
NSString * const kPBSocketKey = @"socket";
NSString * const kPBServerIDKey = @"server-id";
NSString * const kPBClientIDKey = @"client-id";

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
@property (nonatomic, strong) NSMutableDictionary *clientSocketMap;

@property (nonatomic, strong) NSMutableSet *registeredDevices;
@property (nonatomic, strong) NSManagedObjectID *userIdentityObjectID;

@property (nonatomic, strong) NSMutableDictionary *connectedIdentitiesMap;

@property (nonatomic, strong) NSMutableDictionary *socketIdentificationMap;

@end

@implementation PBRemoteMessageManager

- (id)init {
    self = [super init];

    if (self != nil) {

        _maxReadTimeForRawMessages = MAXFLOAT;

        self.clients = [NSMutableDictionary dictionary];
        self.registeredDevices = [NSMutableSet set];
        self.connectedIdentitiesMap = [NSMutableDictionary dictionary];
        self.clientSocketMap = [NSMutableDictionary dictionary];
        self.socketIdentificationMap = [NSMutableDictionary dictionary];

        _maxClients = -1.0f;

        _socketQueue = dispatch_queue_create("socketQueue", NULL);

        self.listenSocket =
        [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];

        self.connectedSockets = [NSMutableArray array];

        self.reachability = [Reachability reachabilityForInternetConnection];
        [self.reachability startNotifier];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(handleIdentificationRequest:)
         name:kPBClientIdentityRequestNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(handleIdentificationResponse:)
         name:kPBClientIdentityResponseNotification
         object:nil];

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

- (NSString *)socketKey:(GCDAsyncSocket *)socket {
    return [NSString stringWithFormat:@"%p", socket];
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

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:_connectedIdentitiesMap.count];

    for (NSManagedObjectID *objectID in _connectedIdentitiesMap.allValues) {

        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithID:objectID];

        if (userIdentity != nil) {
            [result addObject:userIdentity];
        }
    }

    return result;
}

- (GCDAsyncSocket *)socketForUserIdentity:(PBUserIdentity *)userIdentity {

    NSString *clientID = nil;

    for (NSString *deviceID in _connectedIdentitiesMap) {

        NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:deviceID];
        if ([objectID isEqual:userIdentity.objectID]) {
            clientID = deviceID;
            break;
        }
    }

    if (clientID != nil) {
        return [_clientSocketMap objectForKey:clientID];
    }

    return nil;
}

- (void)stop {

    if (_netService != nil) {

        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:kReachabilityChangedNotification
         object:nil];

        [_listenSocket disconnect];

        [_netService stop];

        for (PBRemoteClientInfo *clientInfo in _clients.allValues) {
            [self cleanupClient:clientInfo];
        }

        [_clients removeAllObjects];
        [_connectedIdentitiesMap removeAllObjects];

        @synchronized (_connectedSockets) {
            for (GCDAsyncSocket *socket in _connectedSockets) {
                [socket disconnect];
            }
        }

        [_connectedSockets removeAllObjects];
        [_clientSocketMap removeAllObjects];

        @synchronized (_socketIdentificationMap) {
            [_socketIdentificationMap removeAllObjects];
        }

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

- (void)handleIdentificationRequest:(NSNotification *)notification {

    NSLog(@"received identity request...");

    NSMutableDictionary *userInfo = [notification.userInfo mutableCopy];
    [userInfo setObject:[NSString deviceIdentifier] forKey:kPBClientIDKey];

    if (self.userIdentity != nil) {
        [userInfo addEntriesFromDictionary:
        @{
        kPBUserIdentityUsernameKey : self.userIdentity.username,
        kPBUserIdentityFullNameKey : [NSString safeString:self.userIdentity.fullName],
        kPBUserIdentityEmailKey : [NSString safeString:self.userIdentity.email],
        }];
    }

    NSLog(@"sending identity response...");

    [PBRemoteNotificationMessage
     sendNotification:kPBClientIdentityResponseNotification
     userInfo:userInfo];
}

- (void)handleIdentificationResponse:(NSNotification *)notification {

    NSLog(@"receved identity response...");

    NSString *serverID = [notification.userInfo objectForKey:kPBServerIDKey];
    NSString *clientID = [notification.userInfo objectForKey:kPBClientIDKey];
    NSString *clientSocketKey = [notification.userInfo objectForKey:kPBSocketKey];
    NSString *username = [notification.userInfo objectForKey:kPBUserIdentityUsernameKey];
    NSString *fullName = [notification.userInfo objectForKey:kPBUserIdentityFullNameKey];
    NSString *email = [notification.userInfo objectForKey:kPBUserIdentityEmailKey];

    if ([[NSString deviceIdentifier] isEqualToString:serverID]) {

        if (clientSocketKey != nil) {

            @synchronized (_socketIdentificationMap) {
                [_socketIdentificationMap removeObjectForKey:clientSocketKey];
            }

            for (GCDAsyncSocket *socket in _connectedSockets) {

                NSString *socketKey = [self socketKey:socket];

                if ([socketKey isEqualToString:clientSocketKey]) {
                    [_clientSocketMap setObject:socket forKey:clientID];

                    [[NSNotificationCenter defaultCenter]
                     postNotificationName:kPBRemoteMessageManagerActiveNotification
                     object:self
                     userInfo:nil];

                    if ([_delegate respondsToSelector:@selector(clientConnected:)]) {
                        NSLog(@"device connected: %@", clientID);
                        [_delegate clientConnected:clientID];
                    }

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

                        [_connectedIdentitiesMap setObject:userIdentity.objectID forKey:clientID];
                        
                        if ([_delegate respondsToSelector:@selector(userIdentityConnected:)]) {
                            
                            NSLog(@"user connected: %@", userIdentity.username);
                            [_delegate userIdentityConnected:userIdentity];
                        }
                    }

                    break;
                }
            }

        } else {
            NSLog(@"Error: missing socket value.");
        }
    }
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

        if (self.userIdentity != nil) {
            [self identifySocket:newSocket];
        }

    } else {
        [newSocket disconnect];
    }
}

- (void)identifySocket:(GCDAsyncSocket *)socket {

    NSLog(@"sending identity request...");

    NSDictionary *userInfo =
    @{
    kPBServerIDKey : [NSString deviceIdentifier],
    kPBSocketKey : [self socketKey:socket],
    };

    PBRemoteNotificationMessage *identityRequest =
    [[PBRemoteNotificationMessage alloc]
     initWithNotificationName:kPBClientIdentityRequestNotification
     userInfo:userInfo];

    [self sendMessage:identityRequest recipients:nil socket:socket];

    NSString *socketKey = [self socketKey:socket];

    [_socketIdentificationMap
     setObject:@([NSDate timeIntervalSinceReferenceDate])
     forKey:socketKey];

    int64_t delayInSeconds = 1.0f;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

        @synchronized (_socketIdentificationMap) {

            NSNumber *timestamp =
            [_socketIdentificationMap objectForKey:socketKey];

            if (timestamp != nil) {
                [self identifySocket:socket];
            }
        }
    });
}

- (void)removeSocketMapping:(GCDAsyncSocket *)targetSocket {

    for (NSString *clientID in _clientSocketMap) {

        GCDAsyncSocket *socket = [_clientSocketMap objectForKey:clientID];
        if (socket == targetSocket) {
            [_clientSocketMap removeObjectForKey:clientID];
            break;
        }
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	if (sock != _listenSocket) {
        NSLog(@"Client Disconnected");

        [sock disconnect];
        
		@synchronized(_connectedSockets) {
            [self removeSocketMapping:sock];
			[_connectedSockets removeObject:sock];
		}

        NSString *socketKey = [self socketKey:sock];

        @synchronized (_socketIdentificationMap) {
            [_socketIdentificationMap removeObjectForKey:socketKey];
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

- (void)sendMessage:(PBRemoteMessage *)message
       toRecipients:(NSArray *)recipients {

    for (GCDAsyncSocket *socket in _connectedSockets) {
        [self sendMessage:message recipients:recipients socket:socket];
    }
}

- (void)sendMessage:(PBRemoteMessage *)message {

    for (GCDAsyncSocket *socket in _connectedSockets) {
        [self sendMessage:message recipients:nil socket:socket];
    }
}

- (void)sendMessage:(PBRemoteMessage *)message
         recipients:(NSArray *)recipientList
             socket:(GCDAsyncSocket *)socket {

    NSData *packet = nil;
    BOOL raw = message.rawData != nil;

    if (raw) {
        packet = message.rawData;
    } else {
        NSDictionary *fullMessage =
        @{
        kPBRemoteMessageIDKey : message.messageID,
        kPBRemotePayloadKey : message.payload,
        };

        NSError *error = nil;

        packet =
        [NSPropertyListSerialization
         dataWithPropertyList:fullMessage
         format:NSPropertyListBinaryFormat_v1_0
         options:NSPropertyListMutableContainers
         error:&error];

        if (error != nil) {
            NSLog(@"Error: %@", error);
        }
    }

    if (packet != nil) {

        if (_appendCRLF) {

            NSData *crlfData = [GCDAsyncSocket CRLFData];
            
            NSMutableData *packetCopy = [NSMutableData dataWithCapacity:packet.length + crlfData.length];
            [packetCopy appendData:packet];
            [packetCopy appendData:crlfData];

            packet = packetCopy;
        }
        
        @synchronized (self) {

            // write preamble

            NSData *preamble = raw ? PBRemoteMessage.rawMessagePreamble : PBRemoteMessage.messagePreamble;
            [socket writeData:preamble withTimeout:-1.0f tag:0];

            // write sender

            NSString *sender = [PBRemoteMessageManager sharedInstance].userIdentity.username;

//            NSLog(@"sender: %@", sender);

            uint32_t senderLength = (uint32_t)sender.length;

            NSData *senderLengthData =
            [NSData dataWithBytes:&senderLength length:sizeof(uint32_t)];

            [socket writeData:senderLengthData withTimeout:-1.0f tag:0];
            [socket writeData:[sender dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1.0f tag:0];

            // write recipients

            NSMutableString *recipients = [NSMutableString string];

            for (PBUserIdentity *user in recipientList) {
                if ([user isKindOfClass:[PBUserIdentity class]]) {
                    if (recipients.length > 0) {
                        [recipients appendString:@","];
                    }
                    [recipients appendString:user.username];
                }
            }

//            NSLog(@"sending message with recipients: %@", recipients);

            uint32_t recipientsLength = (uint32_t)recipients.length;

            NSData *recipientsLengthData =
            [NSData dataWithBytes:&recipientsLength length:sizeof(uint32_t)];

            [socket writeData:recipientsLengthData withTimeout:-1.0f tag:0];
            [socket writeData:[recipients dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1.0f tag:0];

            // write packet data

            uint32_t length = (uint32_t)packet.length;
            NSData *lengthData = [NSData dataWithBytes:&length length:sizeof(length)];

            [socket writeData:lengthData withTimeout:-1.0f tag:0];
            [socket writeData:packet withTimeout:-1.0f tag:0];
        }
    } else {
        NSLog(@"Warn: no packet data");
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

            NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:netService.name];

            PBUserIdentity *userIdentity =
            [PBUserIdentity userIdentityWithID:objectID];

            if (userIdentity != nil) {
                NSLog(@"user disconnected: %@", userIdentity.username);
                [_delegate userIdentityDisconnected:userIdentity];
            }
        }

        [_connectedIdentitiesMap removeObjectForKey:netService.name];
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

//    if ([_delegate respondsToSelector:@selector(clientConnected:)]) {
//
//        PBRemoteClientInfo *clientInfo =
//        [self clientInfoForClient:client];
//
//        if (clientInfo.netService.name.length > 0) {
//            [_delegate clientConnected:clientInfo.netService.name];
//        }
//    }
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

                NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:keyToRemove];

                PBUserIdentity *userIdentity =
                [PBUserIdentity userIdentityWithID:objectID];

                if (userIdentity != nil) {
                    NSLog(@"user disconnected: %@", userIdentity.username);
                    [_delegate userIdentityDisconnected:userIdentity];
                }
            }

            [_connectedIdentitiesMap removeObjectForKey:keyToRemove];
        }
        
        [self cleanupClient:clientInfo];

        if ([_delegate respondsToSelector:@selector(clientConnected:)]) {

            if (clientInfo.netService.name.length > 0) {
                NSLog(@"device disconnected: %@", clientInfo.netService.name);
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
