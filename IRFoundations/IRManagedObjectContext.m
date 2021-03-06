//
//  IRManagedObjectContext.m
//  IRFoundations
//
//  Created by Evadne Wu on 2/10/11.
//  Copyright 2011 Iridia Productions. All rights reserved.
//

#import "CoreData+IRAdditions.h"

#import "IRLifetimeHelper.h"
#import "IRManagedObjectContext.h"


@implementation NSManagedObjectContext (IRAdditions)

- (NSManagedObject *) irManagedObjectForURI:(NSURL *)anURI {

	NSManagedObjectID *objectID = [[self persistentStoreCoordinator] managedObjectIDForURIRepresentation:anURI];
		
	if (!objectID)
		return nil;
	
	return [self objectWithID:objectID];

}

@end


@interface IRManagedObjectContext ()

@property (nonatomic, readwrite, assign, setter=irSetAutoMergeStackCount:, getter=irAutoMergeStackCount) NSUInteger irAutoMergeStackCount;
@property (nonatomic, readwrite, strong) id irAutoMergeListener;

@property (nonatomic, readwrite, weak) NSThread *initializingThread;
@property (nonatomic, readwrite, assign) BOOL initializingThreadWasMainThread;

- (void) irAutoMergeSetUp;
- (void) irAutoMergeTearDown;

@end


@implementation IRManagedObjectContext
@synthesize irAutoMergeStackCount, irAutoMergeListener;
@synthesize initializingThread, initializingThreadWasMainThread;

- (id) initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)ct {

	self = [super initWithConcurrencyType:ct];
	self.initializingThread = [NSThread currentThread];
	
	return self;

}

- (void) irPerform:(void(^)(void))block waitUntilDone:(BOOL)sync {

	NSCParameterAssert(block);
	
	switch (self.concurrencyType) {
	
		case NSConfinementConcurrencyType: {
		
			if ([[NSThread currentThread] isEqual:self.initializingThread] && sync) {
				
				block();
				
			} else {
			
				if (!self.initializingThread)
					@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Initialing thread no longer exists" userInfo:nil];
					
				[self performSelector:@selector(irPerformBlock:) onThread:self.initializingThread withObject:[block copy] waitUntilDone:sync modes:@[NSRunLoopCommonModes]];
			
			}
		
			break;
		
		}
		
		case NSPrivateQueueConcurrencyType:
		case NSMainQueueConcurrencyType: {
		
			//	TBD: test
			
			if (sync) {
			
				[self performBlockAndWait:block];
			
			} else {
			
				[self performBlock:block];
			
			}
		
			break;
		
		}

	}

}

- (void) irPerformBlock:(void(^)(void))block {

	NSCParameterAssert(block);
	block();

}

- (void) dealloc {

	if (irAutoMergeListener)
		[[NSNotificationCenter defaultCenter] removeObserver:irAutoMergeListener];

}

- (void) irBeginMergingFromSavesAutomatically {

	self.irAutoMergeStackCount = self.irAutoMergeStackCount + 1;
	
}

- (void) irStopMergingFromSavesAutomatically {

	self.irAutoMergeStackCount = self.irAutoMergeStackCount - 1;

}

- (BOOL) irIsMergingFromSavesAutomatically {

	return !!self.irAutoMergeStackCount;

}

- (void) irSetAutoMergeStackCount:(NSUInteger)newCount {

	NSUInteger oldCount = irAutoMergeStackCount;
	
	[self willChangeValueForKey:@"irAutoMergeStackCount"];
	
	irAutoMergeStackCount = newCount;
	
	if ((oldCount == 0) && (newCount == 1)) {
	
		[self irAutoMergeSetUp];
	
	} else if ((oldCount == 1) && (newCount == 0)) {
	
		[self irAutoMergeTearDown];
	
	}

	[self didChangeValueForKey:@"irAutoMergeStackCount"];
	
}

- (void) irAutoMergeSetUp {

	NSParameterAssert(!self.irAutoMergeListener);

	__weak IRManagedObjectContext *wSelf = self;
	
	self.irAutoMergeListener = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self queue:nil usingBlock: ^ (NSNotification *note) {
			
		[wSelf irAutoMergeHandleManagedObjectContextDidSave:note];
			
	}];
	
}

- (void) irAutoMergeTearDown {
	
	NSParameterAssert(self.irAutoMergeListener);
	[[NSNotificationCenter defaultCenter] removeObserver:self.irAutoMergeListener];
	
	self.irAutoMergeListener = nil;

}

- (void) irAutoMergeHandleManagedObjectContextDidSave:(NSNotification *)note {

	__weak IRManagedObjectContext *wSelf = self;
	
	void (^merge)(void) = ^ {
	
    NSCAssert([NSThread isMainThread], @"This block should run on main thread");
		@try {
 
			NSManagedObjectContext *savedContext = (NSManagedObjectContext *)note.object;
			if (!wSelf.mainContext)
				return;
			
			if (savedContext == wSelf.mainContext)
				return;
			
			if (savedContext.persistentStoreCoordinator != wSelf.mainContext.persistentStoreCoordinator)
				return;
			
			//	Fire faults in wSelf for every single changed object.
			//	This works around an issue where if a NSFetchedResultsController has a predicate, it won’t watch objects changed to fit the predicate
			//	Also fixes production cases where Debug and Release behavior differs
			
			//	Hat tip: http://stackoverflow.com/questions/3923826/nsfetchedresultscontroller-with-predicate-ignores-changes-merged-from-different
			
			[wSelf.mainContext mergeChangesFromContextDidSaveNotification:note];
			
			for (NSManagedObject *object in [note userInfo][NSInsertedObjectsKey])
				[[wSelf.mainContext objectWithID:[object objectID]] willAccessValueForKey:nil];

			for (NSManagedObject *object in [note userInfo][NSUpdatedObjectsKey])
				[[wSelf.mainContext objectWithID:[object objectID]] willAccessValueForKey:nil];

			for (NSManagedObject *object in [note userInfo][NSDeletedObjectsKey])
				[[wSelf.mainContext objectWithID:[object objectID]] willAccessValueForKey:nil];
			
			[wSelf.mainContext processPendingChanges];
	
		} @catch (NSException *exception) {
		
			NSLog(@"%@", exception);
				
		}
				
	};
	
	switch (wSelf.concurrencyType) {
	
		case NSPrivateQueueConcurrencyType:
		case NSConfinementConcurrencyType: {
		
			//	TBD: maybe use an instance method to allow customization of the queue on which things happen
		
			if ([NSThread isMainThread])
				merge();
			else
				dispatch_async(dispatch_get_main_queue(), merge);
		
			break;
		
		}
		
		case NSMainQueueConcurrencyType: {
		
			//	TBD: test
			
			[wSelf performBlockAndWait:merge];
		
			break;
		
		}

	}

}

- (void) irMakeAutoMerging {

	if (![self irIsMergingFromSavesAutomatically]) {
	
		__weak IRManagedObjectContext *wSelf = self;
		
		[self irBeginMergingFromSavesAutomatically];
		[self irPerformOnDeallocation: ^ {
			
			[wSelf irStopMergingFromSavesAutomatically];
			
		}];
	
	}

}

@end
