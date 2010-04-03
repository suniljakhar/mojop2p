#import "MojoAppDelegate.h"
#import "MojoDefinitions.h"
#import "DOMojo.h"
#import "ServiceListController.h"
#import "AboutController.h"
#import "WelcomeController.h"

#import "RHURL.h"
#import "RHCalendarDate.h"
#import "RHDateToStringValueTransformer.h"

#import <Sparkle/Sparkle.h>

@interface MojoAppDelegate (PrivateAPI)
- (BOOL)setupHelperProxy;
- (void)updateDaysLeft:(NSTimer *)timer;
- (void)updateDaysLeftTimer;
@end


@implementation MojoAppDelegate

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		// Register NSValueTransformers
		RHDateToStringValueTransformer *dateToStringTransformer;
		dateToStringTransformer = [[[RHDateToStringValueTransformer alloc] init] autorelease];
		
		// register it with the name that we refer to it with
		[NSValueTransformer setValueTransformer:dateToStringTransformer
										forName:@"RHDateToStringValueTransformer"];
		
		// Update initialization status
		initialized = YES;
	}
}

// SETUP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if((self = [super init]))
	{
		// Create a dictionary to hold the default preferences
		NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
		
		// iTunes Preferences
		[defaultValues setObject:[NSNumber numberWithInt:PLAYLIST_OPTION_FOLDER]  forKey:PREFS_PLAYLIST_OPTION];
		[defaultValues setObject:@"Mojo" forKey:PREFS_PLAYLIST_NAME];
		
		// Advanced Preferences
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_SHOW_REFERRAL_LINKS];
		[defaultValues setObject:[NSNumber numberWithInt:PREFS_REFERRAL_US] forKey:PREFS_REFERRAL_LINK_MODE];
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_DEMO_MODE];
		
		// User Interface Preferences
		[defaultValues setObject:[NSNumber numberWithFloat:1.0F] forKey:PREFS_PLAYER_VOLUME];
		[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:PREFS_TOTAL_TIME];
		
		// Register default values
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
	}
	return self;
}

- (void)awakeFromNib
{
	// Register for the Distributed notifications from MojoHelper
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self
														selector:@selector(mojoHelperIsQuitting:)
															name:@"Quitting"
														  object:@"MojoHelper"];
	
	// Register for notifications from Sparkle
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mojoWillRestartForUpdates:)
												 name:SUUpdaterWillRestartNotification
											   object:nil];
}

// APPLICATION DELEGATE METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// This class extends AppDelegate. Allow it to do any work it needs to do.
	[super applicationDidFinishLaunching:aNotification];
	
	// Create mojo root object (for our side of the distributed object)
	mojoRootObject = [[DOMojo alloc] init];
	
	// Attempt to create helperProxy
	if([self setupHelperProxy] == NO)
	{
		// The MojoHelper application is not running
		// We want to launch the MojoHelper application, and be notified when it's ready
		
		// Register for the appropriate Distributed notifications from MojoHelper
		[[NSDistributedNotificationCenter defaultCenter] addObserver:self
															selector:@selector(mojoHelperIsReady:)
																name:HelperReadyDistributedNotification
															  object:@"MojoHelper"];
		
		// Launch MojoHelper
		NSString *path = [[NSBundle mainBundle] pathForResource:@"MojoHelper" ofType:@"app"];
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:[NSArray arrayWithObject:path]];
	}
	
	// Display welcome message if this is the first time the user has launched mojo
	if(![[NSUserDefaults standardUserDefaults] boolForKey:PREFS_SEEN_WELCOME])
	{
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:PREFS_SEEN_WELCOME];
		
		// Create Welcome Window
		WelcomeController *temp = [[WelcomeController alloc] init];
		[temp showWindow:self];
		
		// Note: WelcomeController will automatically release itself when the user closes the window
	}
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	// This class extends AppDelegate. Allow it to do any work it needs to do.
	[super applicationWillTerminate:aNotification];
	
	// Unregister for distributed notifications
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	
	if(helperProxy != nil)
	{
		// Announce that the helper proxy is about to disappear.
		// This allows parts of the application to use it, if needed, before the app terminates.
		[[NSNotificationCenter defaultCenter] postNotificationName:HelperProxyClosingNotification object:self];
		
		// Close the background application if it's not enabled
		if([helperProxy isBackgroundHelperEnabled] == NO)
		{
			[helperProxy quit];
		}
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
	if(!flag)
	{
		[serviceListWindow makeKeyAndOrderFront:self];
	}
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Application Methods:
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
	NSString *appTempDir = [userTempDir stringByAppendingPathComponent:@"Mojo"];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	if([[NSFileManager defaultManager] fileExistsAtPath:appTempDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:appTempDir attributes:nil];
	}
	
	return appTempDir;
}

/**
 * Returns the port number that our HTTP server is currently running on.
**/
- (int)serverPortNumber
{
	return [helperProxy currentServerPortNumber];
}

/**
 * Returns a reference to the preferences controller.
**/
- (PreferencesController *)preferencesController
{
	return preferencesController;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Utility Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Utility method to convert a standard integer,
 * representing a number of songs,
 * into a formatted human readable string.
**/
- (NSString *)getCountStr:(int)numSongs
{
	if(numSongs == 1)
		return NSLocalizedString(@"1 song", @"Total songs available information");
	else
	{
		NSString *localizedStr = NSLocalizedString(@"%i songs", @"Total songs available information");
		return [NSString stringWithFormat:localizedStr, numSongs];
	}
}

/**
 * Utility method to convert an unsigned 64 bit integer,
 * representing a time in milliseconds,
 * into a formatted human readable string.
**/
- (NSString *)getDurationStr:(uint64_t)totalTime longView:(BOOL)longView
{
	if(longView)
	{
		int days    = (int)(totalTime / (1000 * 60 * 60 * 24));
		int hours   = (int)(totalTime % (1000 * 60 * 60 * 24) / (1000 * 60 * 60));
		int minutes = (int)(totalTime % (1000 * 60 * 60 * 24) % (1000 * 60 * 60) / (1000 * 60));
		int seconds = (int)(totalTime % (1000 * 60 * 60 * 24) % (1000 * 60 * 60) % (1000 * 60) / 1000);
		
		NSMutableString *longView = [NSMutableString stringWithCapacity:4];
		
		if(days > 0)
			[longView appendFormat:@"%i:", days];
		
		if(hours > 0)
		{
			if((hours >= 10) || (days == 0))
				[longView appendFormat:@"%i:", hours];
			else
				[longView appendFormat:@"0%i:", hours];
		}
		
		if((minutes >= 10) || (hours == 0))
			[longView appendFormat:@"%i:", minutes];
		else
			[longView appendFormat:@"0%i:", minutes];
		
		if(seconds >= 10)
			[longView appendFormat:@"%i", seconds];
		else
			[longView appendFormat:@"0%i", seconds];
		
		return [[longView copy] autorelease];
	}
	else
	{
		double days    = (double)totalTime / (double)(1000 * 60 * 60 * 24);
		double hours   = (double)totalTime / (double)(1000 * 60 * 60);
		double minutes = (double)totalTime / (double)(1000 * 60);
		double seconds = (double)totalTime / (double)(1000);
		
		NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
		[formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
		[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
		
		if(days >= 1.0)
		{
			[formatter setMaximumFractionDigits:1];
			NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:days]];
			
			NSString *localizedStr = NSLocalizedString(@"%@ days", @"Total songs available information");
			return [NSString stringWithFormat:localizedStr, temp];
		}
		else if(hours >= 1.0)
		{
			[formatter setMaximumFractionDigits:1];
			NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:hours]];
			
			NSString *localizedStr = NSLocalizedString(@"%@ hours", @"Total songs available information");
			return [NSString stringWithFormat:localizedStr, temp];
		}
		else if(minutes >= 1.0)
		{
			[formatter setMaximumFractionDigits:1];
			NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:minutes]];
			
			NSString *localizedStr = NSLocalizedString(@"%@ minutes", @"Total songs available information");
			return [NSString stringWithFormat:localizedStr, temp];
		}
		else
		{
			[formatter setMaximumFractionDigits:0];
			NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:seconds]];
			
			NSString *localizedStr = NSLocalizedString(@"%@ seconds", @"Total songs available information");
			return [NSString stringWithFormat:localizedStr, temp];
		}
	}
}

/**
 * Utility method to convert an unsigned 64 bit integer,
 * representing a size in bytes,
 * into a formatted human readable string.
**/
- (NSString *)getSizeStr:(uint64_t)totalSize
{
	double GBs = (double)(totalSize) / (double)(1024 * 1024 * 1024);
	double MBs = (double)(totalSize) / (double)(1024 * 1024);
	double KBs = (double)(totalSize) / (double)(1024);
	
	NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
	[formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
	[formatter setNumberStyle:NSNumberFormatterDecimalStyle];
	
	
	if(GBs >= 1.0)
	{
		[formatter setMaximumFractionDigits:2];
		NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:GBs]];
		
		NSString *localizedStr = NSLocalizedString(@"%@ GB", @"Total songs available information");
		return [NSString stringWithFormat:localizedStr, temp];
	}
	else if(MBs >= 1.0)
	{
		[formatter setMaximumFractionDigits:1];
		NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:MBs]];
		
		NSString *localizedStr = NSLocalizedString(@"%@ MB", @"Total songs available information");
		return [NSString stringWithFormat:localizedStr, temp];
	}
	else
	{
		[formatter setMaximumFractionDigits:1];
		NSString *temp = [formatter stringFromNumber:[NSNumber numberWithDouble:KBs]];
		
		NSString *localizedStr = NSLocalizedString(@"%@ KB", @"Total songs available information");
		return [NSString stringWithFormat:localizedStr, temp];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Helper Proxy Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * If the mojo helper app is not running when this app starts, we launch the helper app.
 * When the helper app is ready, it posts a notification, and this method is called.
**/
- (void)mojoHelperIsReady:(NSNotification *)notification
{
	if(helperProxy == nil)
	{
		[self setupHelperProxy];
	}
}

/**
 * When the helper app is quitting, it posts a notification, and this method is called.
**/
- (void)mojoHelperIsQuitting:(NSNotification *)notification
{
	// Post notification of helper proxy closing
	[[NSNotificationCenter defaultCenter] postNotificationName:HelperProxyClosingNotification object:self];
	
	// Close the helper proxy
	helperProxy = nil;
	
	// Mojo can't run without the MojoHelper - time to shut down
	[NSApp terminate:self];
}

/**
 * Method to setup the Distributed Object connection to the MojoHelper application.
**/
- (BOOL)setupHelperProxy
{
	// Create the helper proxy
	NSConnection *doConnection = [NSConnection connectionWithRegisteredName:@"DD:MojoHelper" host:nil];
	[doConnection setReplyTimeout:3.0];
	[doConnection enableMultipleThreads];
	[doConnection setRootObject:mojoRootObject];
	
	helperProxy = [[doConnection rootProxy] retain];
	[helperProxy setProtocolForProxy:@protocol(HelperProtocol)];
	
	if(helperProxy == nil) return NO;
	
	// Post notification that the helperProxy is ready
	[[NSNotificationCenter defaultCenter] postNotificationName:HelperProxyReadyNotification object:self];
	
	return YES;
}

- (NSDistantObject <HelperProtocol> *)helperProxy
{
	return helperProxy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sparkle Updater Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)mojoWillRestartForUpdates:(NSNotification *)notification
{
	// Force the background helper application to quit
	// We will be restarting momentarily
	if(helperProxy != nil)
	{
		[helperProxy quit];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Interface Builder Actions:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)shortUID
{
	CFUUIDRef theUUID = CFUUIDCreate(NULL);
    NSString *fullUID = [(NSString *)CFUUIDCreateString(NULL, theUUID) autorelease];
    CFRelease(theUUID);
	
	return [fullUID substringToIndex:8];
}

- (IBAction)mojoHelp:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_HELP]];
}

@end
