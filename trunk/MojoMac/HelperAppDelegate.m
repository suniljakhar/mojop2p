#import "HelperAppDelegate.h"
#import "MojoDefinitions.h"
#import "Helper.h"
#import "RHKeychain.h"

#import "ITunesLocalSharedData.h"
#import "Subscriptions.h"
#import "ProxyListManager.h"
#import "MojoHTTPServer.h"
#import "BonjourClient.h"
#import "BonjourResource.h"
#import "MojoXMPPClient.h"

#import <TCMPortMapper/TCMPortMapper.h>

#define GROWL_SERVICE_FOUND  @"Service Found"
#define GROWL_SERVICE_LOST   @"Service Lost"

#define GROWL_SUBSCRIPTIONS_UPDATING  @"Updating Subscriptions"
#define GROWL_SUBSCRIPTIONS_UPDATED   @"Subscriptions Updated"


@implementation HelperAppDelegate

// SETUP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if((self = [super init]))
	{
		// Register Default Values
		
		// Create a dictionary to hold the default preferences
		NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
		
		// Default share name is an empty string, meaning it will become the computer name set in system preferences
		[defaultValues setObject:@"" forKey:PREFS_SHARE_NAME];
		
		// We default to having the MojoHelper enabled, and showing. But not launching at login.
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_BACKGROUND_HELPER_ENABLED];
		[defaultValues setObject:[NSNumber numberWithBool:NO]  forKey:PREFS_LAUNCH_AT_LOGIN];
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_DISPLAY_MENU_ITEM];
		
		// We use a deault update interval of every 2 hours
		[defaultValues setObject:[NSNumber numberWithInt:120] forKey:PREFS_UPDATE_INTERVAL];
		
		// Default account information points to the Deusty servers
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_XMPP_AUTOLOGIN];
		
		[defaultValues setObject:DEFAULT_XMPP_SERVER           forKey:PREFS_XMPP_SERVER];
		[defaultValues setObject:[NSNumber numberWithInt:5222] forKey:PREFS_XMPP_PORT];
		
		// Remember: This is the playlist option for subscripitions only
		// We default to not using any playlist options for subscriptions, since they already have their own playlist.
		[defaultValues setObject:[NSNumber numberWithInt:PLAYLIST_OPTION_NONE] forKey:PREFS_PLAYLIST_OPTION];
		[defaultValues setObject:@"Mojo"                                       forKey:PREFS_PLAYLIST_NAME];
		
		// Set the default server port number to zero
		// This allows the server to pick any available open port, and is the most reliable option
		[defaultValues setObject:[NSNumber numberWithInt:0] forKey:PREFS_SERVER_PORT_NUMBER];
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_STUNT_FEEDBACK];
		
		// Register default values
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
		
		// Ensure mandatory STUNT UUID
		NSString *stuntUUID = [[NSUserDefaults standardUserDefaults] stringForKey:STUNT_UUID];
		if(!stuntUUID || [stuntUUID length] < 36)
		{
			CFUUIDRef uuid = CFUUIDCreate(NULL);
			stuntUUID = [(NSString *)CFUUIDCreateString(NULL, uuid) autorelease];
			CFRelease(uuid);
			
			[[NSUserDefaults standardUserDefaults] setObject:stuntUUID forKey:STUNT_UUID];
		}
		
		// Initialize mojoProxy
		mojoProxy = nil;
		
		// Initialize port mapping variables
		serverPortMappingCount = 0;
		
		// Initialize variables used to decide when to display growl notifications
		isStartingApp = YES;
		isGoingToSleep = NO;
		isWakingFromSleep = NO;
	}
	return self;
}

- (void)awakeFromNib
{
	// Initialize Subscriptions
	[Subscriptions initialize];
	
	// Initailize ProxyListUpdater
	[ProxyListManager initialize];
	
	// 
	// Register for NSConnection notifications
	// 
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(connectionDidInitialize:)
												 name:NSConnectionDidInitializeNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(connectionDidDie:)
												 name:NSConnectionDidDieNotification
											   object:nil];
	
	// 
	// Register for BonjourClient notifications
	// 
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didFindLocalService:)
												 name:DidFindLocalServiceNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didUpdateLocalService:)
												 name:DidUpdateLocalServiceNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didRemoveLocalService:)
												 name:DidRemoveLocalServiceNotification
											   object:nil];
	
	// 
	// Register for XMPPClient delegate callbacks
	// 
	[[MojoXMPPClient sharedInstance] addDelegate:self];
	
	// 
	// Register for SubscriptionUpdater notifications
	// 
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(didFindNewSongs:)
//												 name:SubscriptionUpdaterDidFindNewSongsNotification
//											   object:nil];
	
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(didFinishUpdater:)
//												 name:SubscriptionUpdaterDidFinishNotification
//											   object:nil];
	
	// 
	// Register for MojoHTTPServer notification
	// 
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didPublishService:)
												 name:DidPublishServiceNotification
											   object:nil];
	
	// 
	// Register for TCMPortMapper notifications
	// 
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(portMappingDidChange:)
												 name:TCMPortMappingDidChangeMappingStatusNotification
											   object:nil];
}

// APPLICATION DELEGATE METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called after the application has finished launching.
 * By doing most of our code initilaztion here, our app appears to launch much faster.
**/
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// This class extends AppDelegate. Allow it to do any work it needs to do.
	[super applicationDidFinishLaunching:aNotification];
	
	// Update any keychain items if this is a new version of MojoHelper
	[RHKeychain updateAllKeychainItems];
		
	// Setup the growl application bridge
	[GrowlApplicationBridge setGrowlDelegate:self];
	
	// Start bonjour browser
	[[BonjourClient sharedInstance] start];
	
	// Start http server and xmpp client
	// Third parameter is whether or not to start the server(s) afterwards
	[NSThread detachNewThreadSelector:@selector(parseITunesThread:)
							 toTarget:self
						   withObject:[NSNumber numberWithBool:YES]];
	
	// Vend helperInstance as a distributed object
	NSConnection *connection = [NSConnection defaultConnection];
	[connection setRootObject:helper];
	
	if(![connection registerName:@"DD:MojoHelper"])
	{
		NSLog(@"Unable to register MojoHelper DO defaultConnection!!!");
	}
	
	// Now post a distributed notification to let Mojo know it can setup it's proxy connection to us
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:HelperReadyDistributedNotification
																   object:@"MojoHelper"];
	
	// Start the port mapper - It takes a few seconds to get up and running
	[[TCMPortMapper sharedInstance] start];
	
	// And finally start a timer to automatically update the published iTunes info every so often
	NSTimeInterval oneHour = 60 * 60;
	[NSTimer scheduledTimerWithTimeInterval:oneHour
									 target:self
								   selector:@selector(autoUpdateITunesInfo:)
								   userInfo:nil
									repeats:YES];
}

/**
 * Called right before the application terminates.
 * This allows us to perform any necessary cleanup before we quit.
**/
- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	// This class extends AppDelegate. Allow it to do any work it needs to do.
	[super applicationWillTerminate:aNotification];
	
	// Stop any port mappings in progress
	[[TCMPortMapper sharedInstance] stopBlocking];
	
	// Stop http server
	[[MojoHTTPServer sharedInstance] stop];
	
	// Stop bonjour browser
	[[BonjourClient sharedInstance] stop];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Power Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method overrides the stub method in AppDelegate.
**/
- (int)canSystemSleep
{
	if([[MojoHTTPServer sharedInstance] numberOfMojoConnections] > 0)
		return 0;
	else
		return 1;
}

/**
 * Sent to inform us that the system will go to sleep shortly.
**/
- (int)systemWillSleep
{
	isGoingToSleep = YES;
	
	// Todo: Finish implementation of systemWillSleep
	if([[MojoXMPPClient sharedInstance] connectionState] == NSOnState)
	{
		// Send an offline presence notification
		// When the system wakes from sleep, it will properly disconnect, and then immediately reconnect
		[[MojoXMPPClient sharedInstance] goOffline];
		
		// We need to wait until the offline presence message has been sent before we can sleep
		return -1;
	}
	else
	{
		// We're ready to go to sleep right now
		return 1;
	}
}

/**
 * Sent to inform us that the system has recently woken from sleep.
**/
- (void)systemDidWakeFromSleep
{
	isWakingFromSleep = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Application Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates (if necessary) and returns the temporary directory for the application.
 *
 * A general temporary directory is provided for each user by the OS.
 * This prevents conflicts between the same application running on multiple user accounts.
 * We take this a step further by putting everything inside another subfolder, identified by our application name.
**/
- (NSString *)applicationTemporaryDirectory
{
	NSString *userTempDir = NSTemporaryDirectory();
	NSString *appTempDir = [userTempDir stringByAppendingPathComponent:@"MojoHelper"];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	if([[NSFileManager defaultManager] fileExistsAtPath:appTempDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:appTempDir attributes:nil];
	}
	
	return appTempDir;
}

- (NSDistantObject <MojoProtocol> *)mojoProxy
{
	return mojoProxy;
}

/**
 * Returns the port number that our HTTP server is currently running on.
**/
- (int)serverPortNumber
{
	return [[MojoHTTPServer sharedInstance] port];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Port Mapping
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Requests that the server port be mapped.
 * All calls to addServerPortMapping should be balanced with a call to removeServerPortMapping.
 *
 * Returns YES if the port mapping is already setup.
 * Returns NO if the port mapping is not already setup, but will be added. In this case you should listen for
 * TCMPortMappingDidChangeMappingStatusNotification notifications.
**/
- (BOOL)addServerPortMapping
{
	NSLog(@"HelperAppDelegate: addServerPortMapping");
	
	serverPortMappingCount++;
	if(serverPortMappingCount == 1)
	{
		NSLog(@"HelperAppDelegate: adding server port mapping...");
		
		// Add port mapping
		int serverPort = [self serverPortNumber];
		
		serverPortMapping = [[TCMPortMapping alloc] initWithLocalPort:serverPort
												  desiredExternalPort:serverPort
													transportProtocol:TCMPortMappingTransportProtocolTCP
															 userInfo:nil];
		
		[[TCMPortMapper sharedInstance] addPortMapping:serverPortMapping];
		
		return NO;
	}
	else
	{
		return ([serverPortMapping mappingStatus] == TCMPortMappingStatusMapped);
	}
}

- (void)removeServerPortMapping
{
	NSLog(@"HelperAppDelegate: removeServerPortMapping");
	
	serverPortMappingCount--;
	if(serverPortMappingCount == 0 && serverPortMapping != nil)
	{
		NSLog(@"HelperAppDelegate: removing server port mapping...");
		
		// Remove port mapping
		[[TCMPortMapper sharedInstance] removePortMapping:serverPortMapping];
		
		[serverPortMapping release];
		serverPortMapping = nil;
	}
}

- (TCMPortMapping *)serverPortMapping
{
	return [[serverPortMapping retain] autorelease];
}

- (void)portMappingDidChange:(NSNotification *)notification
{
	if([serverPortMapping mappingStatus] == TCMPortMappingStatusMapped)
	{
		NSLog(@"HelperAppDelegate: portMappingDidChange: %i -> %i",
			  [serverPortMapping localPort], [serverPortMapping externalPort]);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSConnection Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)connectionDidInitialize:(NSNotification *)notification
{
	NSConnection *newConnection = (NSConnection *)[notification object];
	
	if(![[mojoProxy connectionForProxy] isValid])
	{
		NSDistantObject *rootProxy = [newConnection rootProxy];
				
		if([rootProxy conformsToProtocol:@protocol(MojoProtocol)])
		{
			[mojoProxy release];
			mojoProxy = [rootProxy retain];
			
			[mojoProxy setProtocolForProxy:@protocol(MojoProtocol)];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:MojoConnectionDidInitializeNotification
																object:self];
		}
	}
}

- (void)connectionDidDie:(NSNotification *)notification
{
	if(![[mojoProxy connectionForProxy] isValid])
	{
		[mojoProxy release];
		mojoProxy = nil;
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MojoConnectionDidDieNotification
															object:self];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Growl Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)applicationNameForGrowl
{
	// We don't want to display "MojoHelper", we want to use simply "Mojo"
	return @"Mojo";
}

- (NSDictionary *)registrationDictionaryForGrowl
{
	NSArray *allNames = [NSArray arrayWithObjects:GROWL_SERVICE_FOUND,
		                                          GROWL_SERVICE_LOST,
												  GROWL_SUBSCRIPTIONS_UPDATING, 
		                                          GROWL_SUBSCRIPTIONS_UPDATED,  nil];
	
	NSArray *defaultNames = [NSArray arrayWithObjects:GROWL_SERVICE_FOUND,
		                                              GROWL_SUBSCRIPTIONS_UPDATED, nil];
	
	NSMutableDictionary *growlDict = [NSMutableDictionary dictionaryWithCapacity:2];
	[growlDict setObject:allNames forKey:GROWL_NOTIFICATIONS_ALL];
	[growlDict setObject:defaultNames forKey:GROWL_NOTIFICATIONS_DEFAULT];
	
	return growlDict;
}

- (void)growlNotificationWasClicked:(id)clickContext
{
	NSDictionary *dict = (NSDictionary *)clickContext;
	NSString *libID = [dict objectForKey:@"libraryID"];
	
	NSString *command = [NSString stringWithFormat:@"tell application \"Mojo\" to view library \"%@\"", libID];
	
	// Note that we don't use NSAppleScript - we don't want to wait for our script to finish
	
	NSMutableArray *args = [NSMutableArray arrayWithCapacity:2];
	[args addObject:@"-e"];
	[args addObject:command];
	
	// Create task
	NSTask *task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:@"/usr/bin/osascript"];
	[task setArguments:args];
	
	// Launch task
	[task launch];
	
	// Note that we do NOT wait for the task to finish
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark BonjourClient Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called when BonjourClient finds a new service.
 * However, if it's a new service, the TXTRecordData isn't available.
 * We have to wait for the service to be updated, at which point we'll know the TXTRecordData.
**/
- (void)didFindLocalService:(NSNotification *)notification
{
	BonjourResource *bonjourResource = (BonjourResource *)[notification object];
	
	// We'll store the name of the service that we just found
	// Now when the service is updated, we'll know that the same service was just found,
	// and we can display a growl notification to the user.
	[lastFoundServiceName release];
	lastFoundServiceName = [[bonjourResource name] copy];
}

- (void)didUpdateLocalService:(NSNotification *)notification
{
	BonjourResource *bonjourResource = (BonjourResource *)[notification object];
	
	if(isStartingApp)
	{
		// We're just starting up the app now, so there's no need to display everyone who's already on the network
		isStartingApp = NO;
	}
	else if(isWakingFromSleep)
	{
		// We always find all of our services again after we wake from sleep.
		// There's no point in displaying notifications to the user in this situation.
		isWakingFromSleep = NO;
	}
	else if(lastFoundServiceName && [lastFoundServiceName isEqualToString:[bonjourResource name]])
	{
		if([[bonjourResource name] isEqualToString:[[BonjourClient sharedInstance] localhostServiceName]])
		{
			// Do nothing, because the service we just found is our own.
		}
		else
		{
			NSString *serviceFoundStr = NSLocalizedStringFromTable(@"Service Found",
			                                                       @"Helper",
			                                                       @"Growl Notification Title");
			
			NSDictionary *dict = [NSDictionary dictionaryWithObject:[bonjourResource libraryID] forKey:@"libraryID"];
			
			[GrowlApplicationBridge notifyWithTitle:serviceFoundStr
										description:[bonjourResource displayName]
								   notificationName:GROWL_SERVICE_FOUND
										   iconData:nil
										   priority:0
										   isSticky:NO
									   clickContext:dict];
		}
	}
	
	[lastFoundServiceName release];
	lastFoundServiceName = nil;
}

- (void)didRemoveLocalService:(NSNotification *)notification
{
	if(isGoingToSleep)
	{
		// We always lose all of our services before we go to sleep.
		// There's no point in displaying notifications to the user in this situation.
		isGoingToSleep = NO;
		return;
	}
	
	BonjourResource *bonjourResource = (BonjourResource *)[notification object];
	
	NSString *serviceLostStr = NSLocalizedStringFromTable(@"Service Lost",
	                                                      @"Helper",
	                                                      @"Growl Notification Title");
	
	[GrowlApplicationBridge notifyWithTitle:serviceLostStr
								description:[bonjourResource displayName]
						   notificationName:GROWL_SERVICE_LOST
								   iconData:nil
								   priority:0
								   isSticky:NO
							   clickContext:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPClient Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppClientConnecting:(XMPPClient *)sender
{
	[mojoProxy postNotificationWithName:XMPPClientConnectingNotification];
}

- (void)xmppClientDidConnect:(XMPPClient *)sender
{
	[mojoProxy postNotificationWithName:XMPPClientDidConnectNotification];
}

- (void)xmppClientDidDisconnect:(XMPPClient *)sender
{
	[mojoProxy postNotificationWithName:XMPPClientDidDisconnectNotification];
}

- (void)xmppClient:(XMPPClient *)sender didNotAuthenticate:(NSXMLElement *)error
{
	[mojoProxy postNotificationWithName:XMPPClientAuthFailureNotification];
}

- (void)xmppClientDidUpdateRoster:(XMPPClient *)sender
{
	[mojoProxy postNotificationWithName:DidUpdateRosterNotification];
}

- (void)xmppClientDidGoOnline:(XMPPClient *)sender
{
	[mojoProxy postNotificationWithName:XMPPClientDidGoOnlineNotification];
}

- (void)xmppClientDidGoOffline:(XMPPClient *)sender
{
	[self replyToSystemWillSleep];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark SubscriptionUpdater Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)didFindNewSongs:(NSNotification *)notification
{
//	SubscriptionsUpdater *updater = [notification object];
//	NSString *displayName = [updater resourceDisplayName];
//	
//	NSString *descriptionStr = NSLocalizedStringFromTable(@"New songs are now being downloaded from %@",
//														  @"Helper",
//														  @"Growl Notification Description");
//	
//	NSString *description = [NSString stringWithFormat:descriptionStr, displayName];
//	
//	NSString *updatingSubscriptionsStr = NSLocalizedStringFromTable(@"Updating Subscriptions",
//																	@"Helper",
//																	@"Growl Notification Title");
//	
//	// Display Growl Notification
//	[GrowlApplicationBridge notifyWithTitle:updatingSubscriptionsStr
//								description:description
//						   notificationName:GROWL_SUBSCRIPTIONS_UPDATING
//								   iconData:nil
//								   priority:0
//								   isSticky:NO
//							   clickContext:nil];
}

- (void)didFinishUpdater:(NSNotification *)aNotification
{
//	SubscriptionsUpdater *updater = [aNotification object];
//	int numberOfSongsDownloaded = [updater numberOfSongsDownloaded];
//	
//	if(numberOfSongsDownloaded > 0)
//	{
//		NSString *displayName = [updater resourceDisplayName];
//		
//		NSString *descriptionStr, *description;
//		
//		if(numberOfSongsDownloaded == 1)
//		{
//			descriptionStr = NSLocalizedStringFromTable(@"1 song downloaded from %@",
//														@"Helper",
//														@"Growl Notification Description");
//			description = [NSString stringWithFormat:descriptionStr, displayName];
//		}
//		else
//		{
//			descriptionStr = NSLocalizedStringFromTable(@"%i songs downloaded from %@",
//														@"Helper",
//														@"Growl Notification Description");
//			description = [NSString stringWithFormat:descriptionStr, numberOfSongsDownloaded, displayName];
//		}
//		
//		NSString *subscriptionsUpdatedStr = NSLocalizedStringFromTable(@"Updating Subscriptions",
//																	   @"Helper",
//																	   @"Growl Notification Title");
//		
//		[GrowlApplicationBridge notifyWithTitle:subscriptionsUpdatedStr
//									description:description
//							   notificationName:GROWL_SUBSCRIPTIONS_UPDATED
//									   iconData:nil
//									   priority:0
//									   isSticky:NO
//								   clickContext:nil];
//	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mojo Server
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)autoUpdateITunesInfo:(NSTimer *)aTimer
{
	[self updateITunesInfo];
}

- (void)updateITunesInfo
{
	// Fork off background thread to handle iTunes parsing
	// Third parameter is whether or not to start the server(s) afterwards - we just want to update them
	[NSThread detachNewThreadSelector:@selector(parseITunesThread:)
							 toTarget:self
						   withObject:[NSNumber numberWithBool:NO]];
}

- (void)forceUpdateITunesInfo
{
	// The ITunesData class keeps a cached version of the localITunesData for a period of several minutes.
	// We want to force it to reparse the information, so we tell it to flush its cache.
	[ITunesLocalSharedData flushSharedLocalITunesData];
	
	// And now we can go through the usual steps of updating the published iTunes info
	[self updateITunesInfo];
}

/**
 * Background thread to handle the potentially CPU intensive operation of parsing the iTunes XML file.
**/
- (void)parseITunesThread:(id)startServers
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSNumber *flag = (NSNumber *)startServers;
	
	ITunesLocalSharedData *data = [ITunesLocalSharedData sharedLocalITunesData];
	
	if([flag boolValue])
	{
		// NOTE: We can't start the MojoHTTPServer on a background thread,
		// because the socket's runloop will disappear when the thread termainates.
		
		// Note that we're forcing this thread to wait for the server to start,
		// just in case somebody tries to immediately quit the MojoHelper right after starting it
		[self performSelectorOnMainThread:@selector(firstParseDidFinish:) withObject:data waitUntilDone:YES];
	}
	else
	{
		[self performSelectorOnMainThread:@selector(subsequentParseDidFinish:) withObject:data waitUntilDone:YES];
	}
	
    [pool release];
}

/**
 * It's important to start the MojoHTTPServer on the primary thread, or else it won't work.
**/
- (void)firstParseDidFinish:(ITunesLocalSharedData *)data
{
	if(data)
	{
		// Extract data
		NSString *libID = [data libraryPersistentID];
		int numSongs = [data numberOfTracks];
		
		// Configure and start MojoHTTPServer
		[[MojoHTTPServer sharedInstance] setITunesLibraryID:libID numberOfSongs:numSongs];
		[[MojoHTTPServer sharedInstance] start:nil];
		
		// Configure XMPPClient
		[[MojoXMPPClient sharedInstance] setITunesLibraryID:libID numberOfSongs:numSongs];
		
		// Only automatically connect if the preference isn't disabled
		if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_AUTOLOGIN])
		{
			[[MojoXMPPClient sharedInstance] start];
		}
	}
	else
	{
		// iTunes XML file not found - Show warning dialog
		[iTunesLibraryNotFoundWarningPanel makeKeyAndOrderFront:self];
	}
}

- (void)subsequentParseDidFinish:(ITunesLocalSharedData *)data
{
	if(data)
	{
		// Extract data
		NSString *libID = [data libraryPersistentID];
		int numSongs = [data numberOfTracks];
		
		// Update MojoHTTPServer
		[[MojoHTTPServer sharedInstance] setITunesLibraryID:libID numberOfSongs:numSongs];
		
		// Update XMPPClient
		[[MojoXMPPClient sharedInstance] setITunesLibraryID:libID numberOfSongs:numSongs];
	}
}

/**
 * When the MojoHTTPServer has successfully published it's bonjour service,
 * it posts a notification, and this method is called.
**/
- (void)didPublishService:(NSNotification *)notification
{
	// The notification object is the NSNetService that was published
	NSNetService *ns = (NSNetService *)[notification object];
	
	// Set the localhost name in the mojo browser
	// This lets the browser exclude the localhost service from it's list
	[[BonjourClient sharedInstance] setLocalhostServiceName:[ns name]];
}

@end
