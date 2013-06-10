//
//  PBRemoteDataManager.m
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright 2012 Pixelbleed. All rights reserved.
//

#import "PBRemoteDataManager.h"

@implementation PBRemoteDataManager

- (NSURL *)urlForFileRelativeToApplicationSupport:(NSString *)relativePath {
    NSError *error = nil;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportDirectory = [paths objectAtIndex:0];

    NSString *executableName =
    [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];

    NSString *path = [appSupportDirectory stringByAppendingPathComponent:executableName];
    path = [path stringByAppendingPathComponent:relativePath];
    NSString *parentPath = [path stringByDeletingLastPathComponent];

	NSURL *url = [NSURL fileURLWithPath:path];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:parentPath] == NO) {

        if ([fileManager createDirectoryAtPath:parentPath
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&error]) {

        } else {
            NSLog(@"Unable to find or create application support directory:\n%@", error);
            url = nil;
        }
    }

    return url;
}

- (NSURL *)persistenceStoreURL {
    NSURL *storePath = [self urlForFileRelativeToApplicationSupport:@"pbremotemessage/PBRemoteMessage.store"];
    return storePath;
}

- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel) {
        return _managedObjectModel;
    }

    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"PBRemoteMessage" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }

    NSManagedObjectModel *model = [self managedObjectModel];
    if (model == nil) {
        NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
        return nil;
    }

    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    NSURL *url = [self persistenceStoreURL];
    NSError *error = nil;

    NSPersistentStore *store = [_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                                         configuration:nil
                                                                                   URL:url
                                                                               options:nil
                                                                                 error:&error];
    if (store == nil) {
        NSLog(@"Failed to create PBRemoteMessage internal persistence store: %@", error);
    }

    return _persistentStoreCoordinator;
}

// Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
- (NSManagedObjectContext *)managedObjectContext {
    if (_managedObjectContext) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];

    if (!coordinator) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setValue:@"Failed to initialize the store" forKey:NSLocalizedDescriptionKey];
        [dict setValue:@"There was an error building up the data file." forKey:NSLocalizedFailureReasonErrorKey];
        NSError *error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        NSLog(@"%@", error);
        return nil;
    }

    _managedObjectContext = [[NSManagedObjectContext alloc]
                             initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    [_managedObjectContext setUndoManager:nil];

    return _managedObjectContext;
}

#pragma mark - Singleton Methods

static dispatch_once_t predicate_;
static PBRemoteDataManager *sharedInstance_ = nil;

+ (id)sharedInstance {
    
    dispatch_once(&predicate_, ^{
        sharedInstance_ = [PBRemoteDataManager alloc];
        sharedInstance_ = [sharedInstance_ init];
    });
    
    return sharedInstance_;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
