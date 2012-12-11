//
//  NSString+GUID.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/8/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (GUID)

- (NSString *)md5Digest;
+ (NSString *)deviceIdentifier;
+ (NSString *)shortDeviceIdentifier;

@end
