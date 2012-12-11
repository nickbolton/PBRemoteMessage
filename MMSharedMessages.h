//
//  MMSharedMessages.h
//  MotionMouse
//
//  Created by Nick Bolton on 12/8/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kMMCalibrationInfoNotification;
extern NSString * const kMMLeftMouseDownNotification;
extern NSString * const kMMLeftMouseUpNotification;
extern NSString * const kMMMotionUpdateNotification;
extern NSString * const kMMCalibrationCompleteNotification;
extern NSString * const kMMStartCalibrationNotification;
extern NSString * const kMMDistanceSoundStartedNotification;
extern NSString * const kMMSnapEnabledNotification;
extern NSString * const kMMSnapDisabledNotification;

@interface MMSharedMessages : NSObject

@end
