//
//  PBRemoteMessagingClient.h
//  RemoteMessage
//
//  Created by Nick Bolton on 12/7/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteMessagingClient.h"
#import "PBRemoteMessageManager.h"
#import "PBRemoteMessage.h"
#import <objc/runtime.h>
#import "PBRemoteNotificationMessage.h"
#import "GCDAsyncSocket.h"
#import "NSString+GUID.h"
#import "PBRemoteNotificationMessage.h"
#import "PBUserIdentity.h"

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

typedef enum {

    MMMessageReadStatePreambleStart = 0,
    MMMessageReadStatePreambleUpdate,
    MMMessageReadStateSenderLength,
    MMMessageReadStateSender,
    MMMessageReadStateRecipientsLength,
    MMMessageReadStateRecipients,
    MMMessageReadStatePacketLength,
    MMMessageReadStatePacket,
    
} MMMessageReadState;

@interface PBRemoteMessagingClient() <NSStreamDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate> {

    BOOL _connected;
    BOOL _started;

    NSTimeInterval _packetReadStartTime;

    MMMessageReadState _messageState;
    BOOL _raw;
    uint32_t _readLength;
}

@property (nonatomic, strong) GCDAsyncSocket *asyncSocket;
@property (nonatomic, strong) NSMutableSet *messageClasses;
@property (nonatomic, strong) NSMutableData *preambleBuffer;
@property (nonatomic, readwrite) NSTimeInterval averageRoundTripTime;
@property (nonatomic, strong) NSString *sender;
@property (nonatomic, strong) NSString *recipientList;

@end

@implementation PBRemoteMessagingClient

- (id)init {
    self = [super init];
    if (self) {
        
        self.messageClasses = [NSMutableSet set];
        self.preambleBuffer = [NSMutableData dataWithCapacity:20];
        
        int numClasses;
        Class * classes = NULL;

        classes = NULL;
        numClasses = objc_getClassList(NULL, 0);

        if (numClasses > 0) {
            classes = (Class *)malloc(sizeof(Class) * numClasses);
            numClasses = objc_getClassList(classes, numClasses);

            for (NSInteger i = 0; i < numClasses; i++) {
                Class clazz = *(classes + i);

                if (class_getSuperclass(clazz) == [PBRemoteMessage class]) {
                    [_messageClasses addObject:clazz];
                }
            }
            free(classes);
        }
    }
    return self;
}

- (void)start {

    if (_started == NO) {

        _started = YES;

        self.asyncSocket =
        [[GCDAsyncSocket alloc]
         initWithDelegate:self
         delegateQueue:dispatch_get_main_queue()];

        [self connectToNextAddress];
    }
}

- (void)stop {

    if (_started) {

        _started = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self];

        [_asyncSocket disconnect];
        self.asyncSocket = nil;
    }
}

- (void)connectToNextAddress {
	BOOL done = NO;

	while (!done && ([_serverAddresses count] > 0)) {
		NSData *addr;

		// Note: The serverAddresses array probably contains both IPv4 and IPv6 addresses.
		//
		// If your server is also using GCDAsyncSocket then you don't have to worry about it,
		// as the socket automatically handles both protocols for you transparently.

		if (YES) {
            // Iterate forwards
			addr = [_serverAddresses objectAtIndex:0];
			[_serverAddresses removeObjectAtIndex:0];
		} else {
            // Iterate backwards
			addr = [_serverAddresses lastObject];
			[_serverAddresses removeLastObject];
		}

		NSLog(@"Attempting connection to %@", addr);

		NSError *err = nil;
		if ([_asyncSocket connectToAddress:addr error:&err]) {
			done = YES;
		} else {
			NSLog(@"Unable to connect: %@", err);
		}
	}

	if (done == NO) {
		NSLog(@"Unable to connect to any resolved address");
        [self stop];
        [_delegate clientDisconnected:self];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
	NSLog(@"Socket:DidConnectToHost: %@ Port: %hu", host, port);

    if (_connected == NO) {
        _connected = YES;
        [_delegate clientConnected:self];
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	NSLog(@"SocketDidDisconnect:WithError: %@", err);

    [self stop];
    [_delegate clientDisconnected:self];

    _connected = NO;
}

- (void)readDataForMessageState:(MMMessageReadState)messageState {

    _messageState = messageState;
    
    switch (_messageState) {
        case MMMessageReadStatePreambleStart:

//            NSLog(@"preamble start, reading 1 byte");

            self.sender = nil;
            self.recipientList = nil;
            
            [_preambleBuffer setLength:0];

            [_asyncSocket
             readDataToLength:1
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStatePreambleUpdate:

//            NSLog(@"preamble update, reading 1 byte");

            [_asyncSocket
             readDataToLength:1
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStateSenderLength:
        case MMMessageReadStateRecipientsLength:
        case MMMessageReadStatePacketLength:

//            NSLog(@"length state, reading %d bytes", sizeof(uint32_t));

            [_asyncSocket
             readDataToLength:sizeof(uint32_t)
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStateSender:
        case MMMessageReadStateRecipients:
        case MMMessageReadStatePacket:

//            NSLog(@"packet state, reading %d bytes", _readLength);

            [_asyncSocket
             readDataToLength:_readLength
             withTimeout:-1.0f
             tag:0];

            break;

        default:
            break;
    }
}

- (void)readDataForNextMessageState {

    MMMessageReadState messageState = _messageState;
    //MMMessageReadState previousState = messageState;
    
    switch (_messageState) {

        case MMMessageReadStatePreambleStart:
            messageState = MMMessageReadStatePreambleUpdate;
            break;

        case MMMessageReadStatePreambleUpdate:
        {
            if (_preambleBuffer.length <= PBRemoteMessage.messagePreamble.length) {

                const void *bufByte = [_preambleBuffer bytes] + _preambleBuffer.length - 1;
                const void *rawPreambleByte = PBRemoteMessage.rawMessagePreamble.bytes + _preambleBuffer.length - 1;
                const void *nonRawPreambleByte = PBRemoteMessage.messagePreamble.bytes + _preambleBuffer.length - 1;

                _raw = *(char *)bufByte == *(char *)rawPreambleByte;

                BOOL nonRaw =
                *(char *)bufByte == *(char *)nonRawPreambleByte;

                if (_raw || nonRaw) {

                    if (_preambleBuffer.length == PBRemoteMessage.messagePreamble.length) {
                        messageState = MMMessageReadStateSenderLength;
                    }
                }
            } else {

                NSLog(@"invalid preamble: %@", _preambleBuffer);

                messageState = MMMessageReadStatePreambleStart;
            }
            break;
        }

        case MMMessageReadStateSenderLength:
            if (_readLength > 0) {
                messageState = MMMessageReadStateSender;
            } else {
                messageState = MMMessageReadStateRecipientsLength;
            }
            break;

        case MMMessageReadStateSender:
            messageState = MMMessageReadStateRecipientsLength;
            break;

        case MMMessageReadStateRecipientsLength:
            if (_readLength > 0) {
                messageState = MMMessageReadStateRecipients;
            } else {
                messageState = MMMessageReadStatePacketLength;
            }
            break;

        case MMMessageReadStateRecipients:
            messageState = MMMessageReadStatePacketLength;
            break;

        case MMMessageReadStatePacketLength:
            messageState = MMMessageReadStatePacket;
            break;

        default:
            messageState = MMMessageReadStatePreambleStart;
            break;
    }

    [self readDataForMessageState:messageState];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
	// This method is executed on the socketQueue (not the main thread)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		@autoreleasepool {

//            NSLog(@"did read %d bytes", data.length);

//            NSLog(@"read data: %@", data);

            switch (_messageState) {
                case MMMessageReadStatePreambleStart:
                case MMMessageReadStatePreambleUpdate:
                    [self readPreamble:data];
                    break;

                case MMMessageReadStateSenderLength:
                case MMMessageReadStateRecipientsLength:
                case MMMessageReadStatePacketLength:
                    [self readDataLength:data];
                    break;

                case MMMessageReadStateSender:
                    [self readSender:data];
                    break;

                case MMMessageReadStateRecipients:
                    [self readRecipients:data];
                    break;

                case MMMessageReadStatePacket:
                    [self readPacket:data];
                    break;

                default:
                    [self readDataForMessageState:MMMessageReadStatePreambleStart];
                    break;
            }
		}
	});
}

- (void)readPreamble:(NSData *)data {
    _packetReadStartTime = [NSDate timeIntervalSinceReferenceDate];
    [_preambleBuffer appendData:data];
    [self readDataForNextMessageState];
}

- (void)readDataLength:(NSData *)data {

    if (data.length == sizeof(uint32_t)) {
        [data getBytes:&_readLength length:sizeof(uint32_t)];
        [self readDataForNextMessageState];
    } else {
        NSLog(@"length data not long enough: %d", data.length);

        _readLength = 0;
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)readSender:(NSData *)data {

    if (data.length == _readLength) {

        if (_readLength > 0) {
            self.sender = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        [self readDataForNextMessageState];

    } else {
        NSLog(@"packet data not long enough: %d != %d", data.length, _readLength);

        _readLength = 0;
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)readRecipients:(NSData *)data {

    if (data.length == _readLength) {

        if (_readLength > 0) {
            self.recipientList = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        [self readDataForNextMessageState];

    } else {
        NSLog(@"packet data not long enough: %d != %d", data.length, _readLength);

        _readLength = 0;
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)readPacket:(NSData *)data {

    if (data.length == _readLength) {

        if ([PBRemoteMessageManager sharedInstance].appendCRLF) {
            data = [data subdataWithRange:NSMakeRange(0, data.length - [GCDAsyncSocket CRLFData].length)];
        }

        NSTimeInterval totalReadTime = [NSDate timeIntervalSinceReferenceDate] - _packetReadStartTime;

        if (_raw == NO || totalReadTime < [PBRemoteMessageManager sharedInstance].maxReadTimeForRawMessages) {

            static NSCharacterSet *commaCharacterSet = nil;

            if (commaCharacterSet == nil) {
                commaCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@","];
            }

            NSArray *recipients =
            [_recipientList
             componentsSeparatedByCharactersInSet:commaCharacterSet];

            NSString *currentUserIdentifier =
            [PBRemoteMessageManager sharedInstance].userIdentity.identifier;

            BOOL peerMessage = [recipients containsObject:currentUserIdentifier];

            if (recipients.count == 0 || peerMessage) {
                if (_raw) {

                    if (_globalDelegate != nil) {
                        [_globalDelegate
                         handleRawMessage:data
                         sender:_sender
                         recipients:recipients
                         peerMessage:peerMessage];

                    } else {
                        NSLog(@"No global delegate to handle raw message.");
                    }

                } else {

                    NSDictionary *packet =
                    [NSPropertyListSerialization
                     propertyListFromData:data
                     mutabilityOption:NSPropertyListImmutable
                     format:NULL
                     errorDescription:NULL];

//                    NSLog(@"read packet: %@", packet);

                    if (packet != nil) {

                        NSString *messageID =
                        [packet objectForKey:kPBRemoteMessageIDKey];

                        NSDictionary *payload =
                        [packet objectForKey:kPBRemotePayloadKey];

                        [self
                         handleMessage:messageID
                         sender:_sender
                         recipients:recipients
                         peerMessage:peerMessage
                         payload:payload];
                        
                    } else {
                        NSLog(@"empty packet: %@", data);
                    }
                }
            }
        } else {
            NSLog(@"packet dropped for exceeding max read time (%f > %f)", totalReadTime, [PBRemoteMessageManager sharedInstance].maxReadTimeForRawMessages);
        }

    } else {
        NSLog(@"packet data not long enough: %d != %d", data.length, _readLength);
    }

    [self readDataForMessageState:MMMessageReadStatePreambleStart];
}

/**
 * This method is called if a read has timed out.
 * It allows us to optionally extend the timeout.
 * We use this method to issue a warning to the user prior to disconnecting them.
 **/
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length {
	return 0.0;
}

- (void)handleMessage:(NSString *)messageID
               sender:(NSString *)sender
           recipients:(NSArray *)recipients
          peerMessage:(BOOL)peerMessage
              payload:(NSDictionary *)payload {

    for (Class clazz in _messageClasses) {

        PBRemoteMessage *message =
        [[clazz alloc]
         initWithMessageID:messageID
         sender:_sender
         recipients:recipients
         peerMessage:peerMessage
         payload:payload];

        if (message != nil) {
            [message consumeMessage];
            break;
        }
    }
}

- (void)dealloc {
    [self stop];
}

@end
