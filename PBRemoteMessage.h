//
//  PBRemoteMessage.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PBRemoteMessage : NSObject

// subclasses must implement the messageID getter
@property (nonatomic, readonly) NSString *messageID;
@property (nonatomic, readonly) NSDictionary *payload;
@property (nonatomic, readonly) NSData *rawData;

+ (NSData *)messagePreamble;
+ (NSData *)rawMessagePreamble;

+ (void)sendRawMessage:(NSData *)data;
+ (void)sendRawMessage:(NSData *)data toRecipients:(NSArray *)recipients;

- (id)initWithMessageID:(NSString *)messageID
                payload:(NSDictionary *)payload;

- (id)initWithRawData:(NSData *)data;

- (id)initWithRawBuffer:(const void *)buffer
                 length:(NSInteger)length;

- (void)consumeMessage;

@end
