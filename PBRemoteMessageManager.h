//
//  PBRemoteMessageManager.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "MMSharedMessages.h"

@class PBRemoteMessage;

extern NSString * const kPBRemoteMessageIDKey;
extern NSString * const kPBRemotePayloadKey;
extern NSString * const kPBRemoteMessageManagerActiveNotification;
extern NSString * const kPBRemoteMessageManagerInactiveNotification;
extern NSString * const kPBPingNotification;
extern NSString * const kPBPongNotification;

@interface PBRemoteMessageManager : NSObject

@property (nonatomic) NSInteger maxClients;

+ (PBRemoteMessageManager *)sharedInstance;

- (void)startWithServiceName:(NSString *)serviceName;
- (void)stop;
- (void)sendBroadcastMessage:(PBRemoteMessage *)message;
- (NSString *)serviceType;

- (NSTimeInterval)averageClientRoundTripTime;

@end
