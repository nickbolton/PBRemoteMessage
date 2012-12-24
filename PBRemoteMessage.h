//
//  PBRemoteMessage.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PBUserIdentity;

@interface PBRemoteMessage : NSObject

// subclasses must implement the messageID getter
@property (nonatomic, readonly) NSString *messageID;
@property (nonatomic, readonly) NSDictionary *payload;
@property (nonatomic, readonly) NSData *rawData;
@property (nonatomic, readonly) NSString *sender;
@property (nonatomic, readonly) NSArray *recipients;
@property (nonatomic, readonly) BOOL peerMessage;

+ (NSData *)messagePreamble;
+ (NSData *)rawMessagePreamble;

+ (void)sendRawMessage:(NSData *)data;
+ (void)sendRawMessage:(NSData *)data toRecipients:(NSArray *)recipients;

- (id)initWithMessageID:(NSString *)messageID
                 sender:(NSString *)sender
             recipients:(NSArray *)recipients
            peerMessage:(BOOL)peerMessage
                payload:(NSDictionary *)payload;

- (id)initWithRawData:(NSData *)data;

- (id)initWithRawBuffer:(const void *)buffer
                 length:(NSInteger)length;

- (void)consumeMessage;

@end
