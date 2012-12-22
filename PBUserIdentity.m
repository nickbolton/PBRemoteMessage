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

@dynamic username;
@dynamic fullName;
@dynamic email;

+ (PBUserIdentity *)userIdentityWithUsername:(NSString *)username {

    NSArray *results = nil;

    if (username.length > 0) {
        NSManagedObjectContext *context =
        [PBRemoteDataManager sharedInstance].managedObjectContext;

        NSEntityDescription *entity =
        [NSEntityDescription
         entityForName:NSStringFromClass([self class])
         inManagedObjectContext:context];

        NSFetchRequest *request = [[NSFetchRequest alloc] init];
        [request setEntity:entity];

        request.predicate =
        [NSPredicate predicateWithFormat:@"username = %@", username];

        NSError *error = nil;

        results = [context executeFetchRequest:request error:&error];
        if (error != nil) {
            NSLog(@"Error: %@", error);
        }
    }

    if (results.count > 0) {
        return [results objectAtIndex:0];
    }
    return nil;
}

+ (PBUserIdentity *)createUserIdentityWithUsername:(NSString *)username
                                          fullName:(NSString *)fullName
                                             email:(NSString *)email {

    if (username.length > 0) {
        NSManagedObjectContext *context =
        [PBRemoteDataManager sharedInstance].managedObjectContext;

        PBUserIdentity *userIdentity =
        [NSEntityDescription
         insertNewObjectForEntityForName:NSStringFromClass([PBUserIdentity class])
         inManagedObjectContext:context];

        userIdentity.username = username;
        userIdentity.fullName = fullName;
        userIdentity.email = email;

        return userIdentity;
    }

    return nil;
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
