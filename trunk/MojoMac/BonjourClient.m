#import "BonjourClient.h"
#import "BonjourResource.h"
#import "MojoDefinitions.h"
#import "HelperAppDelegate.h"
#import "MojoProtocol.h"


@implementation BonjourClient

// CLASS VARIABLES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static BonjourClient *sharedInstance;

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called automatically (courtesy of Cocoa) before the first method of this class is called.
 * It may also called directly, hence the safety mechanism.
**/
+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		sharedInstance = [[BonjourClient alloc] init];
	}
}

/**
 * Returns the shared instance that all objects in this application can use.
**/
+ (BonjourClient *)sharedInstance
{
	return sharedInstance;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard Constructor.
 * This method creates and starts the NSNetServiceBrowser.
**/
- (id)init
{
	// Only allow one instance of this class to ever be created
	if(sharedInstance)
	{
		[self release];
		return nil;
	}
	
	if((self = [super init]))
	{
		// Initialize Bonjour NSNetServiceBrowser - this listens for advertised services
		serviceBrowser = [[NSNetServiceBrowser alloc] init];
		[serviceBrowser setDelegate:self];
		
		// Intialize array to hold all discovered services
		availableResources = [[NSMutableDictionary alloc] init];
	}
	return self;
}

/**
 * Standard Destructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
	[serviceBrowser release];
	[availableResources release];
	[localhostServiceName release];
	[super dealloc];
}

// START, STOP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)start
{
	// Start browsing for mojo bonjour services
	[serviceBrowser searchForServicesOfType:MOJO_SERVICE_TYPE inDomain:@""];
}

- (void)stop
{
	// Stop browsing for services
	[serviceBrowser stop];
	
	// Clear our list of services, so that if we start up again, we won't have duplicates
	[availableResources removeAllObjects];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Correspondence Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)localhostServiceName
{
	return localhostServiceName;
}

- (void)setLocalhostServiceName:(NSString *)newLocalhostServiceName
{
	if(![localhostServiceName isEqualToString:newLocalhostServiceName])
	{
		[localhostServiceName release];
		localhostServiceName = [newLocalhostServiceName copy];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Access:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isLibraryAvailable:(NSString *)libID
{
	BonjourResource *resource = [self resourceForLibraryID:libID];
	
	if(resource)
		return YES;
	else
		return NO;
}

/**
 * Returns the mojo service with the given library.
**/
- (BonjourResource *)resourceForLibraryID:(NSString *)libID
{
	NSArray *keys = [availableResources allKeys];
	
	NSUInteger i;
	for(i = 0; i < [keys count]; i++)
	{
		BonjourResource *currentResource = [availableResources objectForKey:[keys objectAtIndex:i]];
		
		if([libID isEqualToString:[currentResource libraryID]])
		{
			return currentResource;
		}
	}
	return nil;
}

/**
 * Changes the user configured nickname for the given library ID.
 * After the nickname has been updated, this method posts an DidUpdateLocalServiceNotification notification.
**/
- (void)setNickname:(NSString *)nickname forLibraryID:(NSString *)libID
{
	if(libID == nil) return;
	
	// Get the existing dictionary of display names
	// If one does not exist, create an empty dictionary to use
	NSDictionary *nicknames = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PREFS_DISPLAY_NAMES];
	if(!nicknames)
	{
		nicknames = [NSDictionary dictionary];
	}
	
	// Check to see if a name already exists in the dictionary
	NSString *existingNickname = [nicknames objectForKey:libID];
	
	// Only bother updating everything if there is a new nickname
	
	if(![nickname isEqualToString:existingNickname])
	{
		NSMutableDictionary *updatedNicknames = [[nicknames mutableCopy] autorelease];
		[updatedNicknames setObject:nickname forKey:libID];
		
		[[NSUserDefaults standardUserDefaults] setObject:updatedNicknames forKey:PREFS_DISPLAY_NAMES];
		
		// Post notification of updated service
		BonjourResource *updatedResource = [self resourceForLibraryID:libID];
		
		if(updatedResource)
		{
			[[NSNotificationCenter defaultCenter] postNotificationName:DidUpdateLocalServiceNotification
																object:updatedResource];
			[[[NSApp delegate] mojoProxy] postNotificationWithName:DidUpdateLocalServiceNotification];
		}
	}
}

/**
 * Returns an array of BonjourResource objects, representing the available services.
 * The array is left unsorted.
**/
- (NSMutableArray *)unsortedResourcesIncludingLocalhost:(BOOL)flag
{
	NSArray *allValues = [availableResources allValues];
	
	NSMutableArray *unsortedResources = [NSMutableArray arrayWithCapacity:[allValues count]];
	
	NSUInteger i;
	for(i = 0; i < [allValues count]; i++)
	{
		BonjourResource *currentResource = [allValues objectAtIndex:i];
		
		if(flag || ![localhostServiceName isEqualToString:[currentResource name]])
		{
			[unsortedResources addObject:currentResource];
		}
	}
	return unsortedResources;
}

/**
 * Returns an array of BonjourResource objects, representing the available services.
 * The array is sorted in ascending order, according to each service's name.
**/
- (NSMutableArray *)sortedResourcesByNameIncludingLocalhost:(BOOL)flag
{
	NSArray *sortedKeys = [availableResources keysSortedByValueUsingSelector:@selector(compareByName:)];
	
	NSMutableArray *sortedResources = [NSMutableArray arrayWithCapacity:[sortedKeys count]];
	
	NSUInteger i;
	for(i = 0; i < [sortedKeys count]; i++)
	{
		BonjourResource *currentResource = [availableResources objectForKey:[sortedKeys objectAtIndex:i]];
		
		if(flag || ![localhostServiceName isEqualToString:[currentResource name]])
		{
			[sortedResources addObject:currentResource];
		}
	}
	return sortedResources;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSNetServiceBrowser Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)netServiceBrowser:(NSNetServiceBrowser *)sb didFindService:(NSNetService *)ns moreComing:(BOOL)moreComing
{
	// Create new BonjourResource to handle the new net service
	BonjourResource *resource = [[[BonjourResource alloc] initWithNetService:ns] autorelease];
	
	// Add resource to list of available resources
	[availableResources setObject:resource forKey:[ns name]];
	
	// Post notification of new service
	[[NSNotificationCenter defaultCenter] postNotificationName:DidFindLocalServiceNotification object:resource];
	[[[NSApp delegate] mojoProxy] postNotificationWithName:DidFindLocalServiceNotification];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sb didRemoveService:(NSNetService *)ns moreComing:(BOOL)moreComing
{
	// Get corresponding resource for service
	// Notice that we temporarily retain the object so it's not dealloced prior to being used in the notification
	BonjourResource *resource = [[[availableResources objectForKey:[ns name]] retain] autorelease];
	
	// Remove corresponding resource from list of available resources
	[availableResources removeObjectForKey:[ns name]];
	
	// Post notification of removed service
	[[NSNotificationCenter defaultCenter] postNotificationName:DidRemoveLocalServiceNotification object:resource];
	[[[NSApp delegate] mojoProxy] postNotificationWithName:DidRemoveLocalServiceNotification];
}

@end
