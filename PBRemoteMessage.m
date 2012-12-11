//
//  PBRemoteMessage.m
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessage.h"

@interface PBRemoteMessage()

@property (nonatomic, readwrite) NSDictionary *payload;
@property (nonatomic, readwrite) NSString *messageID;

@end

@implementation PBRemoteMessage


- (id)initWithMessageID:(NSString *)messageID
                payload:(NSDictionary *)payload {

    self = [super init];

    if (self != nil) {
        self.messageID = messageID;
        self.payload = payload;
    }

    return self;
}

- (void)consumeMessage {
}

+ (NSString *)messagePreamble {
    static NSString *preamble = @"som";
    return preamble;
}

@end
