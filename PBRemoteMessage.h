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

+ (NSString *)messagePreamble;

- (id)initWithMessageID:(NSString *)messageID
                payload:(NSDictionary *)payload;

- (void)consumeMessage;

@end
