//
//  NSString+GUID.M
//  RemoteMessage
//
//  Created by Nick Bolton on 12/8/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "NSString+GUID.h"
#import <sys/types.h>
#import <stdio.h>
#import <string.h>
#import <sys/socket.h>
#import <net/if_dl.h>
#import <ifaddrs.h>
#import <CommonCrypto/CommonDigest.h>

#if !defined(IFT_ETHER)
#define IFT_ETHER 0x6
#endif

@implementation NSString (GUID)

- (NSString *) md5Digest {
    const char *cStr = [self UTF8String];
    unsigned char result[16];
    CC_MD5( cStr, strlen(cStr), result );
    return [NSString stringWithFormat:
            @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3], 
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ]; 
}

+ (NSString *)macAddress {
    
    char macAddress[18] = { 0 };
    struct ifaddrs* addrs;
    if (!getifaddrs(&addrs)) {
        for (struct ifaddrs* cursor = addrs; cursor; cursor = cursor->ifa_next) {
            if (cursor->ifa_addr->sa_family != AF_LINK) continue;
            if (strcmp("en0", cursor->ifa_name)) continue;
            const struct sockaddr_dl* dlAddr = (const struct sockaddr_dl*)cursor->ifa_addr;
            if (dlAddr->sdl_type != IFT_ETHER) continue;
            const unsigned char* base = (const unsigned char*)&dlAddr->sdl_data[dlAddr->sdl_nlen];
            for (int i = 0; i < dlAddr->sdl_alen; ++i) {
                if (i) {
                    strcat(macAddress, ":");
                }
                char partialAddr[3];
                sprintf(partialAddr, "%02X", base[i]);
                strcat(macAddress, partialAddr);
                
            }
        }
        freeifaddrs(addrs);
    }

    return [NSString stringWithUTF8String:macAddress];
}

+ (NSString *)deviceIdentifier {
    return [[NSString macAddress] md5Digest];
}

+ (NSString *)shortDeviceIdentifier {
    return [[[NSString macAddress] md5Digest] substringFromIndex:23];
}

@end
