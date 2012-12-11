//
//  PBRemoteNotificationMessage.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessage.h"

@interface PBRemoteNotificationMessage : PBRemoteMessage

@property (nonatomic, readonly) NSString *notificationName;
@property (nonatomic, readonly) NSDictionary *userInfo;

- (id)initWithNotificationName:(NSString *)notificationName
                      userInfo:(NSDictionary *)userInfo;

+ (void)sendNotification:(NSString *)notificationName;
+ (void)sendNotification:(NSString *)notificationName
                userInfo:(NSDictionary *)userInfo;

@end
