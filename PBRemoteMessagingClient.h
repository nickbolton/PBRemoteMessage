//
//  PBRemoteMessagingClient.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessageManager.h"

#define END_OF_MSG 0
#define PACKET_MSG 1

@class PBRemoteMessagingClient;

@protocol PBRemoteMessagingClientDelegate <NSObject>

- (void)clientDisconnected:(PBRemoteMessagingClient *)client;

@end

@interface PBRemoteMessagingClient : NSObject

@property (nonatomic, readonly) NSTimeInterval averageRoundTripTime;
@property (nonatomic, strong) NSMutableArray *serverAddresses;
@property (nonatomic, weak) id <PBRemoteMessagingClientDelegate> delegate;
@property (nonatomic, weak) id <PBRemoteMessageDelegate> globalDelegate;

- (void)start;
- (void)stop;

@end
