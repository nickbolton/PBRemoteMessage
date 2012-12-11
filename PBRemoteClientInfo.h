//
//  PBRemoteClientInfo.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/8/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PBRemoteMessagingClient;

@interface PBRemoteClientInfo : NSObject

@property (nonatomic, strong) NSNetService *netService;
@property (nonatomic, strong) PBRemoteMessagingClient *client;

@end
