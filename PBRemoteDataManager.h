//
//  PBRemoteDataManager.h
//  SocialScreen
//
//  Created by Nick Bolton on 12/22/12.
//  Copyright 2012 Pixelbleed. All rights reserved.
//

@interface PBRemoteDataManager : NSObject

@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSManagedObjectContext *globalObjectContext;

- (NSURL *)persistenceStoreURL;
- (NSManagedObjectContext *)managedObjectContext;

+ (PBRemoteDataManager *)sharedInstance;
+ (void)save;

@end
