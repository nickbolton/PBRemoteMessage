//
//  PBUserIdentity.h
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface PBUserIdentity : NSManagedObject

@property (nonatomic, retain) NSString * identifier;
@property (nonatomic, retain) NSString * username;
@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSString * email;

+ (PBUserIdentity *)userIdentityWithID:(NSManagedObjectID *)objectID;
+ (PBUserIdentity *)userIdentityWithIdentifier:(NSString *)identifier;
+ (PBUserIdentity *)createUserIdentityWithIdentifier:(NSString *)identifier
                                            username:(NSString *)username
                                            fullName:(NSString *)fullName
                                               email:(NSString *)email;
+ (void)removeUserIdentityWithID:(NSManagedObjectID *)objectID;

+ (NSArray *)allUsers;

- (void)save;

@end
