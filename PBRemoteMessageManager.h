//
//  PBRemoteMessageManager.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

@class PBRemoteMessage;
@class Reachability;
@class PBUserIdentity;

@protocol PBRemoteMessageDelegate <NSObject>

- (void)handleRawMessage:(NSData *)rawMessageData
                  sender:(NSString *)sender
              recipients:(NSArray *)recipients
             peerMessage:(BOOL)peerMessage;

@optional
- (void)clientConnected:(NSString *)clientDeviceIdentifier;
- (void)clientDisconnected:(NSString *)clientDeviceIdentifier;
- (void)userIdentity:(NSString **)username fullName:(NSString **)fullName email:(NSString **)email;
- (void)userIdentityConnected:(PBUserIdentity *)userIdentity;
- (void)userIdentityDisconnected:(PBUserIdentity *)userIdentity;

@end

extern NSString * const kPBRemoteMessageIDKey;
extern NSString * const kPBRemotePayloadKey;
extern NSString * const kPBRemoteMessageManagerActiveNotification;
extern NSString * const kPBRemoteMessageManagerInactiveNotification;
extern NSString * const kPBPingNotification;
extern NSString * const kPBPongNotification;
extern NSString * const kPBClientIdentityRequestNotification;
extern NSString * const kPBClientIdentityResponseNotification;
extern NSString * const kPBUserIdentityUsernameKey;
extern NSString * const kPBUserIdentityUsernameKey;
extern NSString * const kPBUserIdentityFullNameKey;
extern NSString * const kPBUserIdentityEmailKey;

@interface PBRemoteMessageManager : NSObject

@property (nonatomic) NSInteger maxClients;
@property (nonatomic, weak) id <PBRemoteMessageDelegate> delegate;
@property (nonatomic) BOOL onlyConnectToRegisteredDevices;
@property (nonatomic, strong) NSString *deviceIdentifier;
@property (nonatomic, readonly) Reachability *reachability;
@property (nonatomic, readonly) PBUserIdentity *userIdentity;
@property (nonatomic) NSTimeInterval maxReadTimeForRawMessages;
@property (nonatomic) BOOL appendCRLF;

+ (PBRemoteMessageManager *)sharedInstance;

- (void)startWithServiceName:(NSString *)serviceName;
- (void)stop;
- (void)sendMessage:(PBRemoteMessage *)message;
- (void)sendMessage:(PBRemoteMessage *)message
       toRecipients:(NSArray *)recipients;
- (NSString *)serviceType;
- (void)registeredDevice:(NSString *)deviceIdentifier;
- (void)unregisterDevice:(NSString *)deviceIdentifier;
- (BOOL)isConnectedToClient:(NSString *)clientIdentifier;
- (BOOL)hasConnections;
- (NSTimeInterval)averageClientRoundTripTime;
- (NSArray *)connectedIdentities;

@end
