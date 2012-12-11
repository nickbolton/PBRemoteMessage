//
//  PBRemoteNotificationMessage.m
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteNotificationMessage.h"
#import "PBRemoteMessageManager.h"

NSString * const kPBRemoteNotificationMessageID = @"notification-message";
NSString * const kPBRemoteNotificationNameKey = @"notification-name";
NSString * const kPBRemoteUserInfoKey = @"user-info";

@interface PBRemoteNotificationMessage()

@property (nonatomic, readwrite) NSString *notificationName;
@property (nonatomic, readwrite) NSDictionary *userInfo;

@end

@implementation PBRemoteNotificationMessage

+ (void)sendNotification:(NSString *)notificationName {
    [self sendNotification:notificationName userInfo:nil];
}

+ (void)sendNotification:(NSString *)notificationName
                userInfo:(NSDictionary *)userInfo {

    PBRemoteNotificationMessage *message =
    [[PBRemoteNotificationMessage alloc]
     initWithNotificationName:notificationName
     userInfo:userInfo];

    [[PBRemoteMessageManager sharedInstance]
     sendBroadcastMessage:message];
}

- (id)initWithNotificationName:(NSString *)notificationName
                      userInfo:(NSDictionary *)userInfo {

    if (userInfo == nil) {
        userInfo = @{};
    }    

    NSDictionary *payload =
    @{
    kPBRemoteNotificationNameKey : notificationName,
    kPBRemoteUserInfoKey : userInfo,
    };

    self = [self initWithMessageID:kPBRemoteNotificationMessageID
                           payload:payload];

    return self;
}

- (id)initWithMessageID:(NSString *)messageID
                payload:(NSDictionary *)payload {

    if ([messageID isEqualToString:kPBRemoteNotificationMessageID]) {

        self = [super initWithMessageID:kPBRemoteNotificationMessageID
                                payload:payload];

        if (self != nil) {

            self.notificationName =
            [payload objectForKey:kPBRemoteNotificationNameKey];

            self.userInfo =
            [payload objectForKey:kPBRemoteUserInfoKey];
            
        }
        
        return self;
    }

    return nil;
}

- (void)consumeMessage {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:_notificationName
     object:self
     userInfo:_userInfo];
}

@end
