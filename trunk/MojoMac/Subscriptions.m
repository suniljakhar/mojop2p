#import "Subscriptions.h"
#import "MojoDefinitions.h"
#import "LibrarySubscriptions.h"
#import "BonjourClient.h"
#import "BonjourResource.h"
#import "MojoXMPPClient.h"
#import "RHDate.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 3
#endif
#include "DDLog.h"

@interface Subscriptions (PrivateAPI)
+ (void)saveToUserDefaults;
+ (NSString *)nextLibraryID;
+ (void)updateLibraryWithID:(NSString *)libID;
@end


@implementation Subscriptions

// Stores all the subscriptions
static NSMutableDictionary *librarySubscriptions;

// Stores all the currently running subscription updaters
static NSMutableArray *subscriptionUpdaters;

// Timer that fires when subscriptions are supposed to be updated
static NSTimer *timer;


/**
 * Called automatically (courtesy of Cocoa) before the first method of this class is called.
 * It may also called directly, hence the safety mechanism.
 * 
 * This method reads in the subscriptions from the user defaults system,
 * and converts each subscription to an instance of LibrarySubscriptions.
**/
+ (void)initialize
{
	if(librarySubscriptions == nil)
	{
		DDLogVerbose(@"Initializing Subscriptions...");
		
		// Initialize librarySubscriptions dictionary
		librarySubscriptions = [[NSMutableDictionary alloc] init];
		
		// Initialize subscriptionUpdaters array
		subscriptionUpdaters = [[NSMutableArray alloc] init];
		
		// Get any subscriptions saved to the user defaults system
		NSDictionary *savedLibraries = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PREFS_SUBSCRIPTIONS];
		
		// Now get all the keys for the saved subscriptions
		// Remember, each key is the persistent ID of a library.
		NSArray *allKeys = [savedLibraries allKeys];
		
		int i;
		for(i = 0; i < [allKeys count]; i++)
		{
			NSString *key = [allKeys objectAtIndex:i];
			NSDictionary *dict = [savedLibraries objectForKey:key];
			
			// Make sure we actually have an NSDictionary
			// We could have screwed up somewhere, or someone could be screwing with our plist files
			if([dict isKindOfClass:[NSDictionary class]])
			{
				// Create a new LibrarySubscriptions object with the current dictionary
				LibrarySubscriptions *library = [[LibrarySubscriptions alloc] initWithLibraryID:key dictionary:dict];
				
				// If something went wrong, the number of subscribed playlists will be 0
				// In which case we have no need to keep the library object
				if([library numberOfSubscribedPlaylists] > 0)
				{
					[librarySubscriptions setObject:library forKey:key];
				}
				
				// Release the library.
				// If it was added to the librarySubscriptions dictionary, it's retainCount will still be 1
				[library release];
			}
		}
		
		// Register for notifications
		// When new services become available, we may need to immediately update our subscriptions
		
		// The BonjourClient posts 3 different notifications:
		// DidFindLocalServiceNotification, DidUpdateLocalServiceNotification, DidRemoveLocalServiceNotification
		// 
		// However, when a service is found via Bonjour, we don't have it's txt record yet. So...
		// Since an update notification always follows a find notification, we don't bother registering to the later.
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(didUpdateService:)
													 name:DidUpdateLocalServiceNotification
												   object:nil];
		
		// Register for XMPPClient delegate callbacks
		[[MojoXMPPClient sharedInstance] addDelegate:self];
		
		// We also keep track of all currently running subscription updaters
		// So we need to know when one finishes so we can remove it from our array
	//	[[NSNotificationCenter defaultCenter] addObserver:self
	//											 selector:@selector(subscriptionUpdaterFinished:)
	//												 name:SubscriptionUpdaterDidFinishNotification
	//											   object:nil];
		
		// Note that we don't need to update the timer now
		// This is because the updateTimer: method will automatically be called as services become available
	}
}


/**
 * Returns an array of all the subscriptions.
 * That is, each object in the array will be of type LibrarySubscriptions.
 * The objects in the array are the actual LibrarySubscripitons being used by this class, and as such,
 * should not be modified in any manner.
**/
+ (NSMutableArray *)sortedSubscriptionsByName
{
	NSArray *allKeys = [librarySubscriptions allKeys];
	
	NSMutableArray *sortedArray = [NSMutableArray arrayWithCapacity:[allKeys count]];
	
	int i, j;
	for(i = 0; i < [allKeys count]; i++)
	{
		LibrarySubscriptions *currentUnsortedLS = [librarySubscriptions objectForKey:[allKeys objectAtIndex:i]];
		NSString *currentUnsortedLSName = [currentUnsortedLS displayName];
		
		int insertionIndex = 0;
			
		for(j = 0; j < [sortedArray count]; j++)
		{
			LibrarySubscriptions *currentSortedLS = [sortedArray objectAtIndex:j];
			NSString *currentSortedLSName = [currentSortedLS displayName];
			
			if([currentUnsortedLSName caseInsensitiveCompare:currentSortedLSName] == NSOrderedAscending)
				break;
			else
				insertionIndex++;
		}
		[sortedArray insertObject:currentUnsortedLS atIndex:insertionIndex];
	}
	
	return sortedArray;
}


/**
 * Returns a clone (autoreleased copy) of the LibrarySubscriptions object for the given library.
 * You are free to make any modifications to this object as you wish.
 * If the user is not subscribed to the given library, a new (empty) LibrarySubscriptions object is returned.
**/
+ (LibrarySubscriptions *)subscriptionsCloneForLibrary:(NSString *)libID
{
	LibrarySubscriptions *ls = [librarySubscriptions objectForKey:libID];
	
	if(ls)
	{
		return [[ls copy] autorelease];
	}
	else
	{
		ls = [[[LibrarySubscriptions alloc] initWithLibraryID:libID] autorelease];
		
		// Set the correct name
		BonjourResource *localResource = [[BonjourClient sharedInstance] resourceForLibraryID:libID];
		if(localResource)
		{
			[ls setDisplayName:[localResource displayName]];
		}
		else
		{
			XMPPUserAndMojoResource *remoteResource;
			remoteResource = [[MojoXMPPClient sharedInstance] userAndMojoResourceForLibraryID:libID];
			
			if(remoteResource)
			{
				[ls setDisplayName:[remoteResource mojoDisplayName]];
			}
		}
		
		return ls;
	}
}


/**
 * This method updates the subscriptions to the given library.
 * The information within the LibrarySubscriptions object is assumed to be correct, except the display name.
 * Thus we replace the current LibrarySubscriptions object with a new one for the given library.
 * 
 * We also immediately update the information in the user defaults system.
 * and check to see if any subscriptions need to be updated.
**/
+ (void)setSubscriptions:(LibrarySubscriptions *)subscriptions forLibrary:(NSString *)libID
{
	// Check to see if the given LibrarySubscriptions object actually has any subscriptions in it
	// If it does, then we save it in the dictionary
	// If it doesn't, the there's no use in saving it, and we remove it from the dictionary
	if([subscriptions numberOfSubscribedPlaylists] > 0)
	{
		// We first update the share name for the subscriptions
		BonjourResource *localResource = [[BonjourClient sharedInstance] resourceForLibraryID:libID];
		if(localResource)
		{
			[subscriptions setDisplayName:[localResource displayName]];
		}
		else
		{
			XMPPUserAndMojoResource *remoteResource;
			remoteResource = [[MojoXMPPClient sharedInstance] userAndMojoResourceForLibraryID:libID];
			
			if(remoteResource)
			{
				[subscriptions setDisplayName:[remoteResource mojoDisplayName]];
			}
		}
		
		[librarySubscriptions setObject:subscriptions forKey:libID];
	}
	else
	{
		[librarySubscriptions removeObjectForKey:libID];
	}
	
	// Save the subscriptions to the user defaults system
	[self saveToUserDefaults];
	
	// Since the subscriptions have been changed, the timer may need to be updated
	[self updateTimer:nil];
	
	// Post notification of changed subscriptions
	[[NSNotificationCenter defaultCenter] postNotificationName:SubscriptionsDidChangeNotification object:self];
}


/**
 * This method saves all the subscriptions to the user defaults system.
 * It should be called whenever the subscriptions are changed or updated.
**/
+ (void)saveToUserDefaults
{
	NSArray *allKeys = [librarySubscriptions allKeys];
	
	NSMutableDictionary *defaultsDict = [NSMutableDictionary dictionaryWithCapacity:[allKeys count]];
	
	int i;
	for(i = 0; i < [allKeys count]; i++)
	{
		NSString *key = [allKeys objectAtIndex:i];
		LibrarySubscriptions *library = [librarySubscriptions objectForKey:key];
		
		[defaultsDict setObject:[library prefsDictionary] forKey:key];
	}
	
	[[NSUserDefaults standardUserDefaults] setObject:defaultsDict forKey:PREFS_SUBSCRIPTIONS];
}

/**
 * Returns the library ID of the next subscription that needs to be updated.
 * If a library is not currently available, it can't be updated, and thus won't be considered.
 * Also, if a library is currenly being updated, then we don't know when it will finish, and thus won't be considered.
 *
 * If there are no libraries found (and considered), this method returns nil;
**/
+ (NSString *)nextLibraryID
{
	NSString *nextLibraryID = nil;
	LibrarySubscriptions *nextLibrary = nil;
	
	// Get all the keys for the librarySubscriptions dictionary
	// These are all the library persistent ID's
	NSArray *allKeys = [librarySubscriptions allKeys];
	
	// Now we're going to loop through all the libraries the user is subscribed to
	
	int i;
	for(i = 0; i < [allKeys count]; i++)
	{
		// Get the current key
		// Remember this is the library persistent ID
		NSString *currentKey = [allKeys objectAtIndex:i];
		
		// Only if the library is currently available do we care about it
		BOOL isAvailableOnNetwork = [[BonjourClient sharedInstance] isLibraryAvailable:currentKey];
		BOOL isAvailableOnInternet = [[MojoXMPPClient sharedInstance] isLibraryAvailable:currentKey];
		
		if(isAvailableOnNetwork || isAvailableOnInternet)
		{
			LibrarySubscriptions *currentLibrary = [librarySubscriptions objectForKey:[allKeys objectAtIndex:i]];
			
			// Only if the library is NOT currently being updated do we care about it
			// Otherwise, it can't possibly be next, because it's essentially current
			if(![currentLibrary isUpdating])
			{
				if(nextLibrary == nil)
				{
					nextLibraryID = currentKey;
					nextLibrary = currentLibrary;
				}
				else
				{
					NSDate *oldDate = [nextLibrary lastSyncDate];
					NSDate *newDate = [currentLibrary lastSyncDate];
					
					if([newDate isEarlierDate:oldDate])
					{
						nextLibraryID = currentKey;
						nextLibrary = currentLibrary;
					}
				}
			}
		}
	}
	
	return nextLibraryID;
}


/**
 * This method is called whenever we need to check to see if we should update a subscription.
 * It may be called when:
 * 1. A subscription is added/updated, and we may need to immediately update it.
 * 2. A new mojo service was discovered on the network, so an outdated subscription may be filled now.
 * 3. A timer, scheduled to fire when a subscription should be updated, just fired and called this method.
 * 
 * At any rate, we need to invalidate any previous timers,
 * immediately update any subscriptions that need to be updated,
 * and schedule a timer for the next subscription to be updated if possible.
**/
+ (void)updateTimer:(NSTimer *)aTimer
{
	// Invalidate and release any current timer.
	// We'll reset the timer below if needed.
	[timer invalidate];
	[timer release];
	timer = nil;
	
	BOOL done = NO;
	
	while(!done)
	{
		NSString *nextLibraryID = [self nextLibraryID];
		LibrarySubscriptions *nextLibrary = [librarySubscriptions objectForKey:nextLibraryID];
		
		if(nextLibrary == nil)
		{
			// There are no subscriptions that can be scheduled at this time
			// That is, either no subscriptions exist
			// or the subscriptions that do exist are unavailable or currently being updated
			done = YES;
		}
		else
		{
			DDLogVerbose(@"nextLibraryID: %@ (%@)", nextLibraryID, [nextLibrary displayName]);
			
			NSDate *lastSyncDate = [nextLibrary lastSyncDate];
			NSCalendarDate *lastSync = [lastSyncDate dateWithCalendarFormat:nil timeZone:nil];
			
			int updateIntervalInMinutes = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_UPDATE_INTERVAL];
			
			NSCalendarDate *nextSync = [lastSync dateByAddingYears:0
															months:0
															  days:0
															 hours:0
														   minutes:updateIntervalInMinutes
														   seconds:0];
			
			double timeTilNextSync = [nextSync timeIntervalSinceNow];
			
			if(timeTilNextSync <= 0)
			{
				DDLogInfo(@"Subscriptions: Now updating: %@ (%@)", nextLibraryID, [nextLibrary displayName]);
				
				// The library immediately needs to be updated, so update it now
				[nextLibrary setIsUpdating:YES];
				[self updateLibraryWithID:nextLibraryID];
			}
			else
			{
				DDLogVerbose(@"Subscriptions: Updating subscription at: %@", nextSync);
				
				timer = [NSTimer scheduledTimerWithTimeInterval:timeTilNextSync
														 target:self
													   selector:@selector(updateTimer:)
													   userInfo:nil
														repeats:NO];
				// Retain the timer reference
				// We do this because we might need to invalidate it later
				[timer retain];
				
				// We've now scheduled the timer to fire when the nextLibrary needs to be updated, so we're done
				done = YES;
			}
		}
		
	} // End while
}


/**
 * Description forthcoming...
**/
+ (void)updateLibraryWithID:(NSString *)libID
{
	// Create a new subscription updater for the next library, add start it
//	SubscriptionsUpdater *newUpdater = [[[SubscriptionsUpdater alloc] initWithLibraryID:libID] autorelease];
//	[newUpdater start];
	
	// We now add the updater to our array
//	[subscriptionUpdaters addObject:newUpdater];
}

/**
 * Called (via notification) when a Mojo service is updated.
 * Our job here is to see if we have any subscriptions to the updated service.
 * If we do, then we should update the display name, and update the timer.
**/
+ (void)didUpdateService:(NSNotification *)notification
{
	// The object of the notification is a BonjourResource
	BonjourResource *localResource = [notification object];
	
	// Get the library ID for the resource
	NSString *libraryID = [localResource libraryID];
	
	// Now get the subscriptions associated with the library ID
	// There may, or may not be any subscriptions for this particular library
	LibrarySubscriptions *ls = [librarySubscriptions objectForKey:libraryID];
	
	if(ls)
	{
		// Update the display name for the library
		// This is just for basic bookkeeping - we always want to have the most recent display name
		[ls setDisplayName:[localResource displayName]];
		
		// And now we can update our timer
		// The timer fires when a subscription needs to be updated,
		// and this service may need to be updated sooner than the timer will fire
		[self updateTimer:nil];
	}
}

+ (void)xmppClientDidUpdateRoster:(XMPPClient *)sender
{
	NSArray *remoteResources = [[MojoXMPPClient sharedInstance] sortedUserAndMojoResources];
	
	BOOL found = NO;
	
	NSUInteger i;
	for(i = 0; i < [remoteResources count]; i++)
	{
		XMPPUserAndMojoResource *remoteResource = [remoteResources objectAtIndex:i];
		
		NSString *libraryID = [remoteResource libraryID];
		
		LibrarySubscriptions *ls = [librarySubscriptions objectForKey:libraryID];
		
		if(ls)
		{
			// Update the display name for the library
			// This is just for basic bookkeeping - we always want to have the most recent display name
			[ls setDisplayName:[remoteResource displayName]];
			
			// Make a note that we found an available resource that we have a subscription to
			found = YES;
		}
	}
	
	if(found)
	{
		[self updateTimer:nil];
	}
}

/**
 * Called (via notification) when a subscription updater finishes and posts a SubscriptionUpdaterDidFinishNotification.
 * We registered for this notification in the initialize method.
**/
+ (void)subscriptionUpdaterFinished:(NSNotification *)notification
{
	// The object of the notification is the SubscriptionUpdater that posted the notification
//	SubscriptionsUpdater *oldUpdater = [notification object];
	
	// Since the updater is now finished, we can remove our reference to it
//	[subscriptionUpdaters removeObject:oldUpdater];
	
	// Notice that we don't update the timer at this point.
	// This is because the setSubscriptions:afterAutoUpdateForLibrary: method has already done it for us.
	// This is the method the SubscriptionsUpdater calls immediately prior to posting the current notification.
}

@end
