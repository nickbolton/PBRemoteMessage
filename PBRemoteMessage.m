//
//  PBRemoteMessage.m
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessage.h"
#import "PBRemoteMessageManager.h"

@interface PBRemoteMessage()

@property (nonatomic, readwrite) NSDictionary *payload;
@property (nonatomic, readwrite) NSString *messageID;
@property (nonatomic, readwrite) NSData *rawData;

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

+ (void)sendRawMessage:(NSData *)data {

    PBRemoteMessage *message = [[PBRemoteMessage alloc] initWithRawData:data];

    [[PBRemoteMessageManager sharedInstance]
     sendBroadcastMessage:message];
}

- (id)initWithRawData:(NSData *)data {

    self = [super init];

    if (self != nil) {
        self.rawData = data;
    }

    return self;
}

- (id)initWithRawBuffer:(const void *)buffer
              length:(NSInteger)length {

    NSData *data = [NSData dataWithBytes:buffer length:length];

    return [self initWithRawData:data];
}

- (void)consumeMessage {
}

+ (NSString *)messagePreamble {
    static NSString *preamble = @"som";
    return preamble;
}

@end
