//
//  PBUserIdentity.m
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBUserIdentity.h"
#import "PBRemoteDataManager.h"
#import "PBRemoteMessageManager.h"

@interface PBUserIdentity()
@end

@implementation PBUserIdentity

@dynamic identifier;
@dynamic username;
@dynamic fullName;
@dynamic email;
@dynamic paired;
@dynamic connected;
@dynamic identityType;
@dynamic lastConnected;

+ (NSArray *)userIdentitiesWithPairing:(BOOL)paired {

    NSSortDescriptor *sortDescriptor =
    [NSSortDescriptor sortDescriptorWithKey:@"username" ascending:YES];

    NSArray *results = nil;

    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    NSEntityDescription *entity =
    [NSEntityDescription
     entityForName:NSStringFromClass([self class])
     inManagedObjectContext:context];

    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entity];

    request.predicate =
    [NSPredicate predicateWithFormat:@"paired = %d", paired];

    request.sortDescriptors = @[sortDescriptor];

    results = [self executeRequest:request inContext:context];

    return results;
}

+ (PBUserIdentity *)userIdentityWithIdentifier:(NSString *)identifier {

    NSArray *results = nil;

    if (identifier.length > 0) {
        NSManagedObjectContext *context =
        [PBRemoteDataManager sharedInstance].managedObjectContext;

        NSEntityDescription *entity =
        [NSEntityDescription
         entityForName:NSStringFromClass([self class])
         inManagedObjectContext:context];

        NSFetchRequest *request = [[NSFetchRequest alloc] init];
        [request setEntity:entity];

        request.predicate =
        [NSPredicate predicateWithFormat:@"identifier = %@", identifier];

        results = [self executeRequest:request inContext:context];
    }

    if (results.count > 0) {
        return [results objectAtIndex:0];
    }
    return nil;
}

+ (PBUserIdentity *)createUserIdentityWithIdentifier:(NSString *)identifier
                                            username:(NSString *)username
                                            fullName:(NSString *)fullName
                                               email:(NSString *)email {

    NSAssert(identifier.length > 0, @"identifier is required.");
    NSAssert(username.length > 0, @"username is required.");

    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    PBUserIdentity *userIdentity =
    [NSEntityDescription
     insertNewObjectForEntityForName:NSStringFromClass([PBUserIdentity class])
     inManagedObjectContext:context];

    userIdentity.identifier = identifier;
    userIdentity.username = username;
    userIdentity.fullName = fullName;
    userIdentity.email = email;
    userIdentity.identityType = @(PBUserIdentityTypeUnknown);

    return userIdentity;
}

+ (PBUserIdentity *)userIdentityWithID:(NSManagedObjectID *)objectID {

    if (objectID != nil) {
        NSManagedObjectContext *context =
        [PBRemoteDataManager sharedInstance].managedObjectContext;
        return [context objectWithID:objectID];
    }
    return nil;
}

+ (NSArray *)allUsers {

    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    NSEntityDescription *entity =
    [NSEntityDescription
     entityForName:NSStringFromClass([self class])
     inManagedObjectContext:context];

    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entity];

    return [self executeRequest:request inContext:context];
}

+ (NSArray *)allUsersSortedBy:(NSString *)sortKey filterSelf:(BOOL)filterSelf {
    return
    [self
     allUsersSortedBy:sortKey
     identityType:PBUserIdentityTypeUnknown
     filterSelf:filterSelf
     filterOffline:NO
     includePaired:YES];
}

+ (NSArray *)allUsersSortedBy:(NSString *)sortKey
                 identityType:(PBUserIdentityType)identityType
                   filterSelf:(BOOL)filterSelf
                filterOffline:(BOOL)filterOffline
                includePaired:(BOOL)includePaired {

    NSSortDescriptor *sortDescriptor =
    [NSSortDescriptor sortDescriptorWithKey:sortKey ascending:YES];

    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    NSEntityDescription *entity =
    [NSEntityDescription
     entityForName:NSStringFromClass([self class])
     inManagedObjectContext:context];

    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:entity];

    request.sortDescriptors = @[sortDescriptor];

    if (filterSelf) {
        request.predicate =
        [NSPredicate
         predicateWithFormat:@"self.identifier != %@",
         [PBRemoteMessageManager sharedInstance].deviceIdentifier];
    }

    NSArray * results = [self executeRequest:request inContext:context];

    if (filterOffline) {
        NSMutableArray *mutableResults = [results mutableCopy];

        [mutableResults
         enumerateObjectsWithOptions:NSEnumerationReverse
         usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {

             PBUserIdentity *userIdentity = obj;

             userIdentity =
             [PBUserIdentity userIdentityWithID:userIdentity.objectID];

             if ((userIdentity.connected.boolValue == NO && userIdentity.paired.boolValue == NO) ||
                 (identityType != PBUserIdentityTypeUnknown && identityType != userIdentity.identityType.integerValue)) {
                 [mutableResults removeObjectAtIndex:idx];
             }
         }];

        results = mutableResults;
    }

    return results;
}

+ (NSArray *)executeRequest:(NSFetchRequest *)request
             inContext:(NSManagedObjectContext *)context {

    __block NSArray *results = nil;
    [context performBlockAndWait:^{

        @try {
            NSError *error = nil;
            results = [context executeFetchRequest:request error:&error];

            if (error != nil) {
                NSLog(@"Error: %@", error);
            }

        } @catch (NSException *exception) {
            NSLog(@"Error: %@", exception);
            results = nil;
        }
        
    }];
    
	return results;
}

+ (void)removeUserIdentityWithID:(NSManagedObjectID *)objectID {

    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    PBUserIdentity *userIdentity = [self userIdentityWithID:objectID];

    if (userIdentity != nil) {
        [context deleteObject:userIdentity];
    }

}

- (BOOL)isMacType {
    return self.identityType.integerValue == PBUserIdentityTypeMac;
}

- (BOOL)isiOSType {
    return self.identityType.integerValue == PBUserIdentityTypeiOS;
}

- (void)save {
    NSManagedObjectContext *context =
    [PBRemoteDataManager sharedInstance].managedObjectContext;

    if (self.objectID.isTemporaryID) {

        NSError *error = nil;

        [context obtainPermanentIDsForObjects:@[self] error:&error];

        if (error) {
            NSLog(@"%@", error);
        }
    }

    [context performBlock:^{
        [context save:NULL];
    }];
}

- (void)pair:(void(^)(BOOL paired))completionBlock {
    [[PBRemoteMessageManager sharedInstance] pair:self completion:completionBlock];
}

- (void)unpair {
    [[PBRemoteMessageManager sharedInstance] unpair:self];
}

+ (NSString *)displayName:(PBUserIdentity *)userIdentity {

    NSString *displayName;

    if (userIdentity != nil) {
        if (userIdentity.fullName.length > 0) {
            displayName = userIdentity.fullName;
        } else {
            displayName = userIdentity.username;
        }
    } else {
        displayName = PBLoc(@"Unknown User");
    }
    return displayName;
}

@end
