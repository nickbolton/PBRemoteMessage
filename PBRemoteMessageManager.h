//
//  PBRemoteMessageManager.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

@class PBRemoteMessage;
@class Reachability;

@protocol PBRemoteMessageDelegate <NSObject>

@required
- (void)handleRawMessage:(NSData *)rawMessageData;

@optional
- (void)clientConnected:(NSString *)clientDeviceIdentifier;
- (void)clientDisconnected:(NSString *)clientDeviceIdentifier;

@end

extern NSString * const kPBRemoteMessageIDKey;
extern NSString * const kPBRemotePayloadKey;
extern NSString * const kPBRemoteMessageManagerActiveNotification;
extern NSString * const kPBRemoteMessageManagerInactiveNotification;
extern NSString * const kPBPingNotification;
extern NSString * const kPBPongNotification;

@interface PBRemoteMessageManager : NSObject

@property (nonatomic) NSInteger maxClients;
@property (nonatomic, weak) id <PBRemoteMessageDelegate> delegate;
@property (nonatomic) BOOL onlyConnectToRegisteredDevices;
@property (nonatomic, strong) NSString *deviceIdentifier;
@property (nonatomic, readonly) Reachability *reachability;

+ (PBRemoteMessageManager *)sharedInstance;

- (void)startWithServiceName:(NSString *)serviceName;
- (void)stop;
- (void)sendBroadcastMessage:(PBRemoteMessage *)message;
- (NSString *)serviceType;
- (void)registeredDevice:(NSString *)deviceIdentifier;
- (void)unregisterDevice:(NSString *)deviceIdentifier;
- (BOOL)isConnectedToClient:(NSString *)clientIdentifier;
- (BOOL)hasConnections;
- (NSTimeInterval)averageClientRoundTripTime;

@end
