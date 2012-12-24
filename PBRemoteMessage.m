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
@property (nonatomic, readwrite) NSString *sender;
@property (nonatomic, readwrite) NSArray *recipients;
@property (nonatomic, readwrite) BOOL peerMessage;

@end

@implementation PBRemoteMessage


- (id)initWithMessageID:(NSString *)messageID
                 sender:(NSString *)sender
             recipients:(NSArray *)recipients
            peerMessage:(BOOL)peerMessage
                payload:(NSDictionary *)payload {

    self = [super init];

    if (self != nil) {
        self.messageID = messageID;
        self.payload = payload;
        self.sender = sender;
        self.peerMessage = peerMessage;
        self.recipients = recipients;
    }

    return self;
}

+ (void)sendRawMessage:(NSData *)data {

    PBRemoteMessage *message = [[PBRemoteMessage alloc] initWithRawData:data];

    [[PBRemoteMessageManager sharedInstance]
     sendMessage:message];
}

+ (void)sendRawMessage:(NSData *)data toRecipients:(NSArray *)recipients {

    PBRemoteMessage *message = [[PBRemoteMessage alloc] initWithRawData:data];

    [[PBRemoteMessageManager sharedInstance]
     sendMessage:message toRecipients:recipients];
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

+ (NSData *)messagePreamble {
    static NSData *preamble = nil;
    if (preamble == nil) {
        preamble = [@"som" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return preamble;
}

+ (NSData *)rawMessagePreamble {
    static NSData *preamble = nil;
    if (preamble == nil) {
        preamble = [@"sor" dataUsingEncoding:NSUTF8StringEncoding];
    }
    return preamble;
}

@end
