//
//  PBRemoteMessageManager.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

@class PBRemoteMessage;

@protocol PBRemoteMessageDelegate <NSObject>

- (void)handleRawMessage:(NSData *)rawMessageData;

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

+ (PBRemoteMessageManager *)sharedInstance;

- (void)startWithServiceName:(NSString *)serviceName;
- (void)stop;
- (void)sendBroadcastMessage:(PBRemoteMessage *)message;
- (NSString *)serviceType;

- (NSTimeInterval)averageClientRoundTripTime;

@end
