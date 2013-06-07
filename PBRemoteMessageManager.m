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
#import "NSString+PBFoundation.h"
#import "PBUserIdentity.h"

#define READ_TIMEOUT 15.0

NSString * const kPBRemoteMessageIDKey = @"message-id";
NSString * const kPBRemotePayloadKey = @"payload";
NSString * const kPBRemoteMessageManagerActiveNotification =
@"kPBRemoteMessageManagerActiveNotification";
NSString * const kPBRemoteMessageManagerInactiveNotification =
@"kPBRemoteMessageManagerInactiveNotification";
NSString * const kPBRemoteMessageManagerUserConnectedNotification =
@"kPBRemoteMessageManagerUserConnectedNotification";
NSString * const kPBRemoteMessageManagerUserDisconnectedNotification =
@"kPBRemoteMessageManagerUserDisconnectedNotification";
NSString * const kPBPingNotification = @"kPBPingNotification";
NSString * const kPBPongNotification = @"kPBPongNotification";
NSString * const kPBClientIdentityRequestNotification = @"kPBClientIdentityRequestNotification";
NSString * const kPBClientIdentityResponseNotification = @"kPBClientIdentityResponseNotification";
NSString * const kPBPairingStatusRequestNotification = @"kPBPairingStatusRequestNotification";
NSString * const kPBPairingStatusResponseNotification = @"kPBPairingStatusResponseNotification";
NSString * const kPBPairingUpdateNotification = @"kPBPairingUpdateNotification";
NSString * const kPBPairingRequestNotification = @"kPBPairingRequestNotification";
NSString * const kPBUnpairingRequestNotification = @"kPBUnpairingRequestNotification";
NSString * const kPBPairingAcceptedNotification = @"kPBPairingAcceptedNotification";
NSString * const kPBPairingDeniedNotification = @"kPBPairingDeniedNotification";
NSString * const kPBRemoteMessageManagerPairingRequestedNotification = @"kPBRemoteMessageManagerPairingRequestedNotification";
NSString * const kPBUserIdentityIdentifierKey = @"userIdentity-identifier";
NSString * const kPBUserIdentityUsernameKey = @"userIdentity-username";
NSString * const kPBUserIdentityFullNameKey = @"userIdentity-fullName";
NSString * const kPBUserIdentityEmailKey = @"userIdentity-email";
NSString * const kPBUserIdentityTypeKey = @"userIdentity-type";
NSString * const kPBUserIdentityNewUserKey = @"userIdentity-new";
NSString * const kPBSocketKey = @"socket";
NSString * const kPBServerIDKey = @"server-id";
NSString * const kPBClientIDKey = @"client-id";
NSString * const kPBPairedIdentitiesKey = @"paired-identities";
NSString * const kPBPairedStatusKey = @"is-paired";

@interface PBRemoteMessageManager()
<NSNetServiceBrowserDelegate, NSNetServiceDelegate, PBRemoteMessagingClientDelegate>  {

    dispatch_queue_t _socketQueue;
    BOOL _starting;
    void (^_pairingCompletionBlock)(BOOL paired);
}

@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) GCDAsyncSocket *listenSocket;
@property (nonatomic, strong) NSMutableArray *connectedSockets;
@property (nonatomic, strong) NSArray *pairedIdentities;

@property (nonatomic, readwrite) Reachability *reachability;
@property (nonatomic, strong) NSString *serviceName;

@property (nonatomic, strong) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, strong) NSMutableDictionary *clients;
@property (nonatomic, strong) NSMutableDictionary *clientSocketMap;

@property (nonatomic, strong) NSManagedObjectID *userIdentityObjectID;
@property (nonatomic, readwrite) NSString *userIdentifier;

@property (nonatomic, strong) NSMutableDictionary *connectedIdentitiesMap;

@property (nonatomic, strong) NSMutableDictionary *socketIdentificationMap;

@end

@implementation PBRemoteMessageManager

- (id)init {
    self = [super init];

    if (self != nil) {

        _maxReadTimeForRawMessages = MAXFLOAT;

        self.clients = [NSMutableDictionary dictionary];
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

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingRequest:)
         name:kPBPairingRequestNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(unpairingRequest:)
         name:kPBUnpairingRequestNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingAccepted:)
         name:kPBPairingAcceptedNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingDenied:)
         name:kPBPairingDeniedNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingUpdate:)
         name:kPBPairingUpdateNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingStatusRequest:)
         name:kPBPairingStatusRequestNotification
         object:nil];

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(pairingStatusResponse:)
         name:kPBPairingStatusResponseNotification
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

- (NSString *)serviceType {
    return [NSString stringWithFormat:@"_%@._tcp.", _serviceName];
}

- (void)startWithServiceName:(NSString *)serviceName {

    if (_netService == nil) {

        PBUserIdentity *userIdentity = nil;

        for (userIdentity in [PBUserIdentity allUsers]) {
            userIdentity.connected = @(NO);
        }

        [userIdentity save];

        if ([_delegate respondsToSelector:@selector(userIdentity:username:fullName:email:)]) {

            NSString *identifier = nil;
            NSString *username = nil;
            NSString *fullName = nil;
            NSString *email = nil;

            [_delegate
             userIdentity:&identifier
             username:&username
             fullName:&fullName
             email:&email];

            if (identifier.length > 0) {

                PBUserIdentity *userIdentity =
                [PBUserIdentity userIdentityWithIdentifier:identifier];

                if (userIdentity == nil) {
                    userIdentity =
                    [PBUserIdentity
                     createUserIdentityWithIdentifier:identifier
                     username:username
                     fullName:fullName
                     email:email];
                } else {
                    userIdentity.fullName = fullName;
                    userIdentity.email = email;
                }

#if TARGET_OS_IPHONE
                userIdentity.identityType = @(PBUserIdentityTypeiOS);
#else
                userIdentity.identityType = @(PBUserIdentityTypeMac);
#endif

                [userIdentity save];
                self.userIdentityObjectID = userIdentity.objectID;
                self.userIdentifier = identifier;
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

- (PBUserIdentity *)userIdentityForSocket:(GCDAsyncSocket *)socket {

    for (NSString *deviceID in _connectedIdentitiesMap) {

        GCDAsyncSocket *connectedSocket = [_clientSocketMap objectForKey:deviceID];
        if (socket == connectedSocket) {
            NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:deviceID];
            if (objectID != nil) {
                return [PBUserIdentity userIdentityWithID:objectID];
            }
        }
    }

    return nil;
}

- (NSString *)clientIDForUserIdentity:(PBUserIdentity *)userIdentity {
    NSString *clientID = nil;

    for (NSString *deviceID in _connectedIdentitiesMap) {

        NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:deviceID];
        if ([objectID isEqual:userIdentity.objectID]) {
            clientID = deviceID;
            break;
        }
    }

    return clientID;
}

- (GCDAsyncSocket *)socketForUserIdentity:(PBUserIdentity *)userIdentity {

    NSString *clientID = [self clientIDForUserIdentity:userIdentity];

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

- (void)pairingRequest:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    PBRemoteNotificationMessage *message = notification.object;

    self.pairedIdentities =
    [message.userInfo objectForKey:kPBPairedIdentitiesKey];

    PBUserIdentity *sender =
    [PBUserIdentity userIdentityWithIdentifier:message.sender];

    [[NSNotificationCenter defaultCenter]
     postNotificationName:kPBRemoteMessageManagerPairingRequestedNotification
     object:sender
     userInfo:nil];

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);
}

- (void)unpairingRequest:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    PBRemoteNotificationMessage *message = notification.object;

    PBUserIdentity *sender =
    [PBUserIdentity userIdentityWithIdentifier:message.sender];
    sender.paired = @(NO);
    [sender save];

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);
}

- (void)pairingAccepted:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    @synchronized (self) {

        PBRemoteNotificationMessage *message = notification.object;

        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithIdentifier:message.sender];

        userIdentity.paired = @(YES);
        [userIdentity save];

        if (_pairingCompletionBlock != nil) {
            _pairingCompletionBlock(YES);
            _pairingCompletionBlock = nil;
        }
    }

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);

    [self sendPairingUpdateNotification];
}

- (void)pairingDenied:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    @synchronized (self) {

        PBRemoteNotificationMessage *message = notification.object;

        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithIdentifier:message.sender];

        userIdentity.paired = @(NO);
        [userIdentity save];

        if (_pairingCompletionBlock != nil) {
            _pairingCompletionBlock(NO);
            _pairingCompletionBlock = nil;
        }
    }

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);
}

- (void)pairingUpdate:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    NSArray *pairedIdentities =
    [notification.userInfo objectForKey:kPBPairedIdentitiesKey];

    PBUserIdentity *pairedIdentity = nil;
    
    for (NSString *identity in pairedIdentities) {

        if ([identity isEqualToString:self.deviceIdentifier] == NO) {

            pairedIdentity = [PBUserIdentity userIdentityWithIdentifier:identity];

            if (pairedIdentity == nil) {

                pairedIdentity =
                [PBUserIdentity
                 createUserIdentityWithIdentifier:identity
                 username:@""
                 fullName:@""
                 email:@""];
            }

            pairedIdentity.paired = @(YES);
        }
    }

    [pairedIdentity save];
}

- (void)pairingStatusRequest:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);

    PBRemoteNotificationMessage *message = notification.object;

    PBUserIdentity *sender =
    [PBUserIdentity userIdentityWithIdentifier:message.sender];

    if (sender != nil) {

        BOOL isPaired = sender.paired.boolValue;

        [PBRemoteNotificationMessage
         sendNotification:kPBPairingStatusResponseNotification
         userInfo:@{
         kPBPairedStatusKey : @(isPaired),
         }
         toRecipients:@[sender]];
    }
}

- (void)pairingStatusResponse:(NSNotification *)notification {
    NSLog(@"%s", __PRETTY_FUNCTION__);

    PBRemoteNotificationMessage *message = notification.object;

    PBUserIdentity *sender =
    [PBUserIdentity userIdentityWithIdentifier:message.sender];

    if (sender != nil) {

        NSNumber *isPaired = [message.userInfo objectForKey:kPBPairedStatusKey];

        sender.paired = isPaired;
        [sender save];
    }

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);
}

- (void)handleIdentificationRequest:(NSNotification *)notification {

    NSLog(@"received identity request...");

    NSMutableDictionary *userInfo = [notification.userInfo mutableCopy];
    [userInfo setObject:[NSString deviceIdentifier] forKey:kPBClientIDKey];

    if (self.userIdentity != nil) {
        [userInfo addEntriesFromDictionary:
        @{
        kPBUserIdentityIdentifierKey : self.userIdentity.identifier,
        kPBUserIdentityUsernameKey : self.userIdentity.username,
        kPBUserIdentityFullNameKey : [NSString safeString:self.userIdentity.fullName],
        kPBUserIdentityEmailKey : [NSString safeString:self.userIdentity.email],
#if TARGET_OS_IPHONE
        kPBUserIdentityTypeKey : @(PBUserIdentityTypeiOS),
#else
        kPBUserIdentityTypeKey : @(PBUserIdentityTypeMac),
#endif
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
    NSString *identifier = [notification.userInfo objectForKey:kPBUserIdentityIdentifierKey];
    NSString *username = [notification.userInfo objectForKey:kPBUserIdentityUsernameKey];
    NSString *fullName = [notification.userInfo objectForKey:kPBUserIdentityFullNameKey];
    NSString *email = [notification.userInfo objectForKey:kPBUserIdentityEmailKey];
    NSNumber *identityType = [notification.userInfo objectForKey:kPBUserIdentityTypeKey];

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

                    if (identifier.length > 0) {
                        PBUserIdentity *userIdentity =
                        [PBUserIdentity userIdentityWithIdentifier:identifier];

                        BOOL newUser = userIdentity == nil;

                        if (newUser) {
                            userIdentity =
                            [PBUserIdentity
                             createUserIdentityWithIdentifier:identifier
                             username:username
                             fullName:fullName
                             email:email];
                        } else {
                            userIdentity.fullName = fullName;
                            userIdentity.email = email;
                        }

                        userIdentity.identityType = identityType;
                        userIdentity.connected = @(YES);

                        [userIdentity save];

                        [_connectedIdentitiesMap setObject:userIdentity.objectID forKey:clientID];
                        
                        if ([_delegate respondsToSelector:@selector(userIdentityConnected:)]) {
                            
                            NSLog(@"user connected: %@", userIdentity.identifier);
                            [_delegate userIdentityConnected:userIdentity];
                        }

                        [[NSNotificationCenter defaultCenter]
                         postNotificationName:kPBRemoteMessageManagerUserConnectedNotification
                         object:self
                         userInfo:
                         @{
                         kPBUserIdentityIdentifierKey : userIdentity.identifier,
                         kPBUserIdentityNewUserKey : @(newUser),
                         }];

                        NSTimeInterval delayInSeconds = 1.0f;
                        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                            [self sendPairingStatusRequestNotification];
                        });
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

- (void)doUserDisconnected:(PBUserIdentity *)userIdentity {

    userIdentity.connected = @(NO);

    [userIdentity save];

    if (userIdentity != nil) {

        NSLog(@"user disconnected: %@", userIdentity.identifier);

        if ([_delegate respondsToSelector:@selector(userIdentityDisconnected:)]) {
            [_delegate userIdentityDisconnected:userIdentity];
        }

        [[NSNotificationCenter defaultCenter]
         postNotificationName:kPBRemoteMessageManagerUserDisconnectedNotification
         object:self
         userInfo:
         @{
         kPBUserIdentityIdentifierKey : userIdentity.identifier,
         }];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	if (sock != _listenSocket) {
        NSLog(@"Client Disconnected");

        PBUserIdentity *userIdentity = [self userIdentityForSocket:sock];

        [self doUserDisconnected:userIdentity];

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

    if (recipients.count == 0) {
        [self sendMessage:message];
    } else {

        for (PBUserIdentity *userIdentity in recipients) {

            GCDAsyncSocket *socket = [self socketForUserIdentity:userIdentity];

            if ([_connectedSockets containsObject:socket]) {
                [self sendMessage:message recipients:recipients socket:socket];
            }
        }
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

            // write send timestamp

            NSTimeInterval timestamp = [NSDate timeIntervalSinceReferenceDate];
            NSLog(@"sending message with timestamp: %f", timestamp);
            uint32_t integerPortion = floor(timestamp);
            uint32_t decimalPortion = floor((timestamp - integerPortion) * 1000000);

            NSLog(@"sending message with integerPortion: %d", integerPortion);
            NSLog(@"sending message with decimalPortion: %d", decimalPortion);

            NSData *sendTimestampIntegerData =
            [NSData dataWithBytes:&integerPortion length:sizeof(uint32_t)];
            NSData *sendTimestampDecimalData =
            [NSData dataWithBytes:&decimalPortion length:sizeof(uint32_t)];

            [socket writeData:sendTimestampIntegerData withTimeout:-1.0f tag:0];
            [socket writeData:sendTimestampDecimalData withTimeout:-1.0f tag:0];

            // write sender

            NSString *sender = [PBRemoteMessageManager sharedInstance].userIdentifier;

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
                    [recipients appendString:user.identifier];
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

- (BOOL)isPairedWithDeviceIdentifier:(NSString *)deviceIdentifier {

    NSArray *pairedIdentities =
    [PBUserIdentity userIdentitiesWithPairing:YES];

    for (PBUserIdentity *userIdentity in pairedIdentities) {
        if ([userIdentity.identifier isEqualToString:deviceIdentifier]) {
            return YES;
        }
    }

    return NO;
}

- (void)pair:(PBUserIdentity *)userIdentity completion:(void(^)(BOOL paired))completionBlock {

    if (_pairingCompletionBlock == nil && [userIdentity.identifier isEqualToString:self.deviceIdentifier] == NO) {
        _pairingCompletionBlock = completionBlock;

        NSDictionary *userInfo = nil;

        if (_propagatePairings) {
            NSArray *pairings = [PBUserIdentity userIdentitiesWithPairing:YES];
            if (pairings.count > 0) {
                NSMutableArray *pairedIdentities =
                [NSMutableArray arrayWithCapacity:pairings.count];

                for (PBUserIdentity *pairedIdentity in pairings) {
                    [pairedIdentities addObject:pairedIdentity.identifier];
                }

                userInfo =
                @{
                  kPBPairedIdentitiesKey : pairedIdentities,
                };
            }
        }

        [PBRemoteNotificationMessage
         sendNotification:kPBPairingRequestNotification
         userInfo:userInfo
         toRecipients:@[userIdentity]];

        NSTimeInterval delayInSeconds = 20.0f;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

            @synchronized (self) {
                if (_pairingCompletionBlock != nil) {
                    _pairingCompletionBlock(NO);
                    _pairingCompletionBlock = nil;
                }
            }
        });
    }
}

- (void)unpair:(PBUserIdentity *)userIdentity {

    userIdentity.paired = @(NO);
    [userIdentity save];

    [PBRemoteNotificationMessage
     sendNotification:kPBUnpairingRequestNotification
     toRecipients:@[userIdentity]];

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);
}

- (void)acceptPairing:(PBUserIdentity *)userIdentity {

    if ([userIdentity.identifier isEqualToString:self.deviceIdentifier] == NO) {
        for (NSString *identity in self.pairedIdentities) {

            if ([identity isEqualToString:self.deviceIdentifier] == NO) {

                PBUserIdentity *pairedIdentity = [PBUserIdentity userIdentityWithIdentifier:identity];

                if (pairedIdentity == nil) {

                    pairedIdentity =
                    [PBUserIdentity
                     createUserIdentityWithIdentifier:identity
                     username:@""
                     fullName:@""
                     email:@""];
                }

                pairedIdentity.paired = @(YES);
            }
        }

        userIdentity.paired = @(YES);
        [userIdentity save];

        [PBRemoteNotificationMessage
         sendNotification:kPBPairingAcceptedNotification
         toRecipients:@[userIdentity]];
    }

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);

    self.pairedIdentities = nil;
}

- (void)denyPairing:(PBUserIdentity *)userIdentity {

    if ([userIdentity.identifier isEqualToString:self.deviceIdentifier] == NO) {

        userIdentity.paired = @(NO);
        [userIdentity save];
        
        [PBRemoteNotificationMessage
         sendNotification:kPBPairingDeniedNotification
         toRecipients:@[userIdentity]];
    }

    NSLog(@"paired identities: %@", [PBUserIdentity userIdentitiesWithPairing:YES]);

    self.pairedIdentities = nil;
}

- (void)sendPairingUpdateNotification {

    NSArray *pairings =
    [PBUserIdentity userIdentitiesWithPairing:YES];

    if (pairings.count > 0) {
        NSMutableArray *pairedIdentities =
        [NSMutableArray arrayWithCapacity:pairings.count];

        for (PBUserIdentity *pairedIdentity in pairings) {
            [pairedIdentities addObject:pairedIdentity.identifier];
        }

        [PBRemoteNotificationMessage
         sendNotification:kPBPairingUpdateNotification
         userInfo:@{
         kPBPairedIdentitiesKey : pairedIdentities,
         }
         toRecipients:pairings];
    }
}

- (void)sendPairingStatusRequestNotification {

    NSArray *pairings =
    [PBUserIdentity userIdentitiesWithPairing:YES];

    if (pairings.count > 0) {
        [PBRemoteNotificationMessage
         sendNotification:kPBPairingStatusRequestNotification
         toRecipients:pairings];
    }
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

            NSArray *pairedIdentities =
            [PBUserIdentity userIdentitiesWithPairing:YES];
            
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

    if ([netService.name isEqualToString:self.deviceIdentifier] == NO) {

        NSLog(@"DidRemoveService: %@", [netService name]);

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForService:netService];

        [clientInfo.client stop];

        [_clients removeObjectForKey:netService.name];

        NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:netService.name];

        PBUserIdentity *userIdentity =
        [PBUserIdentity userIdentityWithID:objectID];

        [self doUserDisconnected:userIdentity];

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

    if (self.userIdentity == nil) {

        [[NSNotificationCenter defaultCenter]
         postNotificationName:kPBRemoteMessageManagerActiveNotification
         object:self
         userInfo:nil];

        PBRemoteClientInfo *clientInfo =
        [self clientInfoForClient:client];

        PBUserIdentity *clientIdentity =
        [PBUserIdentity userIdentityWithIdentifier:clientInfo.netService.name];

        clientIdentity.connected = @(YES);

        [clientIdentity save];

        if ([_delegate respondsToSelector:@selector(clientConnected:)]) {

            if (clientInfo.netService.name.length > 0) {
                [_delegate clientConnected:clientInfo.netService.name];
            }
        }
    }
}

- (void)clientDisconnected:(PBRemoteMessagingClient *)client {

    PBRemoteClientInfo *clientInfo =
    [self clientInfoForClient:client];

    PBUserIdentity *clientIdentity =
    [PBUserIdentity userIdentityWithIdentifier:clientInfo.netService.name];

    clientIdentity.connected = @(NO);
    [clientIdentity save];

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

            NSManagedObjectID *objectID = [_connectedIdentitiesMap objectForKey:keyToRemove];

            PBUserIdentity *userIdentity =
            [PBUserIdentity userIdentityWithID:objectID];

            [self doUserDisconnected:userIdentity];

            [_connectedIdentitiesMap removeObjectForKey:keyToRemove];
        }
        
        [self cleanupClient:clientInfo];

        if ([_delegate respondsToSelector:@selector(clientDisconnected:)]) {

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
