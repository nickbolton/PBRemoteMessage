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
     sendMessage:message];
}

+ (void)sendNotification:(NSString *)notificationName
            toRecipients:(NSArray *)recipients {
    [self sendNotification:notificationName userInfo:nil toRecipients:recipients];
}

+ (void)sendNotification:(NSString *)notificationName
                userInfo:(NSDictionary *)userInfo
            toRecipients:(NSArray *)recipients {

    PBRemoteNotificationMessage *message =
    [[PBRemoteNotificationMessage alloc]
     initWithNotificationName:notificationName
     userInfo:userInfo];

    [[PBRemoteMessageManager sharedInstance]
     sendMessage:message toRecipients:recipients];
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

    self = [self
            initWithMessageID:kPBRemoteNotificationMessageID
            sender:nil
            recipients:nil
            peerMessage:NO
            payload:payload];

    return self;
}

- (id)initWithMessageID:(NSString *)messageID
                 sender:(NSString *)sender
             recipients:(NSArray *)recipients
            peerMessage:(BOOL)peerMessage
                payload:(NSDictionary *)payload {

    if ([messageID isEqualToString:kPBRemoteNotificationMessageID]) {

        self = [super
                initWithMessageID:kPBRemoteNotificationMessageID
                sender:sender
                recipients:recipients
                peerMessage:peerMessage
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

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:_notificationName
         object:self
         userInfo:_userInfo];
    });
}

@end
