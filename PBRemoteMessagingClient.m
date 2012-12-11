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
#import "DDLog.h"
#import "NSString+GUID.h"
#import "PBRemoteNotificationMessage.h"

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

typedef enum {

    MMMessageReadStatePreambleStart = 0,
    MMMessageReadStatePreambleUpdate,
    MMMessageReadStateLength,
    MMMessageReadStatePacket,
    
} MMMessageReadState;

@interface PBRemoteMessagingClient() <NSStreamDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate> {

    BOOL _connected;
    BOOL _started;

    NSTimeInterval _pingStartedTime;
    NSTimeInterval _roundTripRunningTime;
    NSInteger _roundTripCount;
    NSInteger _timeoutCount;

    MMMessageReadState _messageState;
    uint32_t _packetLength;
}

@property (nonatomic, strong) GCDAsyncSocket *asyncSocket;
@property (nonatomic, strong) NSMutableSet *messageClasses;
@property (nonatomic, strong) NSMutableString *preambleBuffer;
@property (nonatomic, readwrite) NSTimeInterval averageRoundTripTime;

@end

@implementation PBRemoteMessagingClient

- (id)init {
    self = [super init];
    if (self) {

        self.messageClasses = [NSMutableSet set];
        self.preambleBuffer = [NSMutableString string];
        
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

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(handlePong:)
         name:kPBPongNotification
         object:nil];

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

- (void)handlePong:(NSNotification *)notification {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    _roundTripRunningTime += (now - _pingStartedTime);
    _roundTripCount++;
    _averageRoundTripTime = _roundTripRunningTime / _roundTripCount;
    _pingStartedTime = 0;
}

- (void)sendPing {

    if (_started) {
        static NSTimeInterval pingTimeout = 1.0f;
        static NSInteger maxTimeouts = 3;

        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        _pingStartedTime = now;

        [PBRemoteNotificationMessage
         sendNotification:kPBPingNotification];

        int64_t delayInSeconds = pingTimeout;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

            if (_pingStartedTime == now) {

                // timeout
                NSLog(@"timeout!");

                _timeoutCount++;

                if (_timeoutCount >= maxTimeouts) {

                    NSLog(@"max timeouts reached!");

                    [self stop];
                    if (_started) {
                        [self start];
                    }
                }
            } else {
                _timeoutCount = 0;
                [self sendPing];
            }
        });
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
        [self sendPing];
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	NSLog(@"SocketDidDisconnect:WithError: %@", err);

	if (_connected) {
        _connected = NO;
		[self connectToNextAddress];
	} else {
        [self stop];
        [_delegate clientDisconnected:self];
    }
}

- (void)readDataForMessageState:(MMMessageReadState)messageState {

    _messageState = messageState;
    
    switch (_messageState) {
        case MMMessageReadStatePreambleStart:

//            NSLog(@"preamble start, reading 1 byte");

            _preambleBuffer.string = @"";

            [_asyncSocket
             readDataToLength:1.0f
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStatePreambleUpdate:

//            NSLog(@"preamble update, reading 1 byte");

            [_asyncSocket
             readDataToLength:1.0f
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStateLength:

//            NSLog(@"length state, reading %d bytes", sizeof(uint32_t));

            [_asyncSocket
             readDataToLength:sizeof(uint32_t)
             withTimeout:-1.0f
             tag:0];

            break;

        case MMMessageReadStatePacket:

//            NSLog(@"packet state, reading %d bytes", _packetLength);

            [_asyncSocket
             readDataToLength:_packetLength
             withTimeout:-1.0f
             tag:0];

            break;

        default:
            NSLog(@"ZZZZ");
            break;
    }
}

- (void)readDataForNextMessageState {

    MMMessageReadState messageState = _messageState;
    
    switch (_messageState) {

        case MMMessageReadStatePreambleStart:
            messageState = MMMessageReadStatePreambleUpdate;
            break;

        case MMMessageReadStatePreambleUpdate:
        {
            if (_preambleBuffer.length <= PBRemoteMessage.messagePreamble.length &&
                [_preambleBuffer isEqualToString:[PBRemoteMessage.messagePreamble substringToIndex:_preambleBuffer.length]]) {

                if (_preambleBuffer.length == PBRemoteMessage.messagePreamble.length) {
                    messageState = MMMessageReadStateLength;
                }
            } else {

                NSLog(@"invalid preamble: %@", _preambleBuffer);

                messageState = MMMessageReadStatePreambleStart;
            }
            break;
        }

        case MMMessageReadStateLength:
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

                case MMMessageReadStateLength:
                    [self readPacketLength:data];
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

    NSString *preamblePart = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    if (preamblePart.length > 0) {
        [_preambleBuffer appendString:preamblePart];
    }

    [self readDataForNextMessageState];
}

- (void)readPacketLength:(NSData *)data {

    if (data.length == sizeof(uint32_t)) {
        [data getBytes:&_packetLength length:sizeof(uint32_t)];
        [self readDataForNextMessageState];
    } else {
        NSLog(@"length data not long enough: %d", data.length);

        _packetLength = 0;
        [self readDataForMessageState:MMMessageReadStatePreambleStart];
    }
}

- (void)readPacket:(NSData *)data {

    if (data.length == _packetLength) {

        NSDictionary *packet =
        [NSPropertyListSerialization
         propertyListFromData:data
         mutabilityOption:NSPropertyListImmutable
         format:NULL
         errorDescription:NULL];

//        NSLog(@"read packet: %@", packet);

        if (packet != nil) {

            NSString *messageID =
            [packet objectForKey:kPBRemoteMessageIDKey];

            NSDictionary *payload =
            [packet objectForKey:kPBRemotePayloadKey];

            [self handleMessage:messageID payload:payload];
            
        } else {
            NSLog(@"transaction was emtpy, data: %@", data);
        }
    } else {
        NSLog(@"packet data not long enough: %d != %d", data.length, _packetLength);
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

- (void)handleMessage:(NSString *)messageID payload:(NSDictionary *)payload {

    for (Class clazz in _messageClasses) {

        PBRemoteMessage *message =
        [[clazz alloc] initWithMessageID:messageID
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
