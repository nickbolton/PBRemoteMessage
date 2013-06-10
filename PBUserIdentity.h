//
//  PBUserIdentity.h
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

typedef enum {
    PBUserIdentityTypeUnknown = 0,
    PBUserIdentityTypeMac,
    PBUserIdentityTypeiOS,
} PBUserIdentityType;

@interface PBUserIdentity : NSManagedObject

@property (nonatomic, strong) NSString * identifier;
@property (nonatomic, strong) NSString * username;
@property (nonatomic, strong) NSString * fullName;
@property (nonatomic, strong) NSString * email;
@property (nonatomic, strong) NSNumber * paired;
@property (nonatomic, strong) NSNumber * connected;
@property (nonatomic, strong) NSNumber * identityType;
@property (nonatomic, strong) NSDate   * lastConnected;

+ (PBUserIdentity *)userIdentityWithID:(NSManagedObjectID *)objectID;
+ (PBUserIdentity *)userIdentityWithIdentifier:(NSString *)identifier;
+ (PBUserIdentity *)createUserIdentityWithIdentifier:(NSString *)identifier
                                            username:(NSString *)username
                                            fullName:(NSString *)fullName
                                               email:(NSString *)email;
+ (NSArray *)userIdentitiesWithPairing:(BOOL)pairing;
+ (void)removeUserIdentityWithID:(NSManagedObjectID *)objectID;

+ (NSArray *)allUsers;
+ (NSArray *)allUsersSortedBy:(NSString *)sortKey filterSelf:(BOOL)filterSelf;
+ (NSArray *)allUsersSortedBy:(NSString *)sortKey
                 identityType:(PBUserIdentityType)identityType
                   filterSelf:(BOOL)filterSelf
                filterOffline:(BOOL)filterOffline
                includePaired:(BOOL)includePaired;
+ (NSString *)displayName:(PBUserIdentity *)userIdentity;

- (void)pair:(void(^)(BOOL paired))completionBlock;
- (void)unpair;
- (void)save;
- (BOOL)isMacType;
- (BOOL)isiOSType;

@end
