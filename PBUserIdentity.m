//
//  PBUserIdentity.m
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright (c) 2012 Pixelbleed. All rights reserved.
//

#import "PBUserIdentity.h"
#import "PBRemoteDataManager.h"

@implementation PBUserIdentity

@dynamic identifier;
@dynamic username;
@dynamic fullName;
@dynamic email;

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

    return userIdentity;
}

+ (PBUserIdentity *)userIdentityWithID:(NSManagedObjectID *)objectID {

    if (objectID != nil) {
        NSManagedObjectContext *context =
        [PBRemoteDataManager sharedInstance].managedObjectContext;

        NSError *error = nil;

        PBUserIdentity *userIdentity =
        (id)[context
             existingObjectWithID:objectID
             error:&error];

        if (error != nil) {
            NSLog(@"Error: %@", error);
        }
        
        return userIdentity;
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

@end
