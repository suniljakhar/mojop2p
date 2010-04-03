#import "AppDelegate.h"

#import <mach/mach_port.h>
#import <mach/mach_interface.h>
#import <mach/mach_init.h>

#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/IOMessage.h>


// Callback function to be invoked by the OS for power notifications
void callback(void * x, io_service_t y, natural_t messageType, void * messageArgument);

// Reference to the Root Power Domain IOService
io_connect_t root_port;

// Notification port allocated by IORegisterForSystemPower
IONotificationPortRef notifyPortRef;

// Notifier object, created when registering for power notifications, and used to deregister later
io_object_t notifierObject;


@interface AppDelegate (PrivateAPI)
- (void)registerForPowerNotifications;
- (void)deregisterForPowerNotifications;
- (int)canSystemSleep;
- (int)systemWillSleep;
- (void)systemDidWakeFromSleep;
@end


/**
 * This class implements the common methods shared between both AppDelegates.
 * This ensures that both Mojo and MojoHelper share a common code base, 
 * as well as a common application support directory.
**/
@implementation AppDelegate

// APPLICATION DELEGATE METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self registerForPowerNotifications];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	[self deregisterForPowerNotifications];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Power Management:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called by the System whenever a power event occurs.
 * Code courtesy Apple. (Wayne Flansburg)
**/
void callback(void * x, io_service_t y, natural_t messageType, void * messageArgument)
{
	AppDelegate *selfRef = (AppDelegate *)x;
	
	long notificationID = (long)messageArgument;
	
    switch(messageType)
	{
		case kIOMessageCanSystemSleep:
			// In this case, the computer has been idle for several minutes
			// and will sleep soon so you must either allow or cancel
			// this notification. Important: if you don't respond, there will
			// be a 30-second timeout before the computer sleeps.
			selfRef->lastCanSystemSleepNotificationID = notificationID;
			
			int canSystemSleepResult = [selfRef canSystemSleep];
			if(canSystemSleepResult > 0)
			{
				IOAllowPowerChange(root_port, (long)messageArgument);
			}
			else if(canSystemSleepResult == 0)
			{
				IOCancelPowerChange(root_port, (long)messageArgument);
			}
			break;
			
		case kIOMessageSystemWillSleep:
			// Handle demand sleep, such as:
			// A. Running out of batteries
			// B. Closing the lid of a laptop
			// C. Selecting sleep from the Apple menu
			selfRef->lastSystemWillSleepNotificationID = notificationID;
			
			int systemWillSleepResult = [selfRef systemWillSleep];
			if(systemWillSleepResult > 0)
			{
				IOAllowPowerChange(root_port, (long)messageArgument);
			}
			break;
			
		case kIOMessageSystemHasPoweredOn:
			[selfRef systemDidWakeFromSleep];
			break;
	}
}

/**
 * Registers for power notifications from the OS.
 * This includes notification of when the system will go to sleep, and when it will wake up.
 * We need to know this to keep our timers in sync.
**/
- (void)registerForPowerNotifications
{
	// Register for system power notifications
	root_port = IORegisterForSystemPower(self, &notifyPortRef, callback, &notifierObject);
	if(root_port == (int)NULL)
	{
		NSLog(@"IORegisterForSystemPower failed!");
	}
	
	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopDefaultMode);
}

/**
 * Deregisters for power notifications.
 * This method should be called before the application terminates.
**/
- (void)deregisterForPowerNotifications
{
	// Remove the sleep notification port from the application runloop
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes);
	
    // Deregister for system sleep notifications
    IODeregisterForSystemPower(&notifierObject);
	
    // IORegisterForSystemPower implicitly opens the Root Power Domain IOService, so we close it here
    IOServiceClose(root_port);
	
    // destroy the notification port allocated by IORegisterForSystemPower
    IONotificationPortDestroy(notifyPortRef);
}

/**
 * Returns whether or not the system can go to sleep.
 * Return 1 (or any positive number) to immediately reply, and allow the system to go to sleep.
 * Return 0 to immediately reply, and prevent the system from going to sleep.
 * Return -1 (or any negative number) to delay the reply until a later time.
 * In this case, one should invoke replyToCanSystemSleepWithResult: within 30 seconds.
 * 
 * Note that if you delay the response, and do nothing within 30 seconds,
 * then the system will act as if you had asked to prevent sleep.
**/
- (int)canSystemSleep
{
	// Override me to do something here...
	return 1;
}

/**
 * Invoke this method within 30 seconds of delaying the response to the canSystemSleep notification.
 * See the canSystemSleep: method for more information.
**/
- (void)replyToCanSystemSleepWithResult:(BOOL)flag
{
	if(flag)
		IOAllowPowerChange(root_port, lastCanSystemSleepNotificationID);
	else
		IOCancelPowerChange(root_port, lastCanSystemSleepNotificationID);
}

/**
 * Sent to inform us that the system will go to sleep shortly.
 * Return 1 (or any positive number) to immediately reply, and allow the system to go to sleep.
 * Return -1 (or any negative number) to delay the reply until a later time.
 * In this case, one should invoke replyToSystemWillSleep: within 30 seconds.
 * 
 * Note that there is no way to prevent the system from going to sleep.
 * If you return a 0, the system will still go to sleep, but sleep may be delayed up to 30 seconds.
 * This behaviour is not recommended. (Read: looked down upon)
**/
- (int)systemWillSleep
{
	// Override me to do something here...
	return 1;
}

/**
 * Invoke this method within 30 seconds of delaying the response to the systemWillSleep notification.
 * See the systemWillSleep: method for more information.
**/
- (void)replyToSystemWillSleep
{
	IOAllowPowerChange(root_port, lastSystemWillSleepNotificationID);
}

/**
 * Sent to inform us that the system has recently woken from sleep.
**/
- (void)systemDidWakeFromSleep
{
	// Override me to do something here...
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Application Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)applicationSupportDirectory
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *appSupportDir = [basePath stringByAppendingPathComponent:@"Mojo"];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:appSupportDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:appSupportDir attributes:nil];
    }
	
	return appSupportDir;
}

/**
 * Returns whether or not the currently running application is Mojo (and not MojoHelper).
**/
- (BOOL)isMojo
{
	NSDictionary *infoPlistDict = [[NSBundle mainBundle] infoDictionary];
	return [[infoPlistDict objectForKey:@"CFBundleName"] isEqualToString:@"Mojo"];
}

/**
 * Returns whether or not the currently running application is MojoHelper (and not Mojo).
**/
- (BOOL)isMojoHelper
{
	NSDictionary *infoPlistDict = [[NSBundle mainBundle] infoDictionary];
	return [[infoPlistDict objectForKey:@"CFBundleName"] isEqualToString:@"MojoHelper"];
}

/**
 * Returns the path to the Mojo application.
 * This method may be called by either the Mojo or MojoHelper application.
 * This method will still work properly if called by the MojoHelper application when it's the active target in Xcode
**/
- (NSString *)mojoPath
{
	if([self isMojo])
	{
		// This method is being called from the Mojo application
		
		NSString *mojoPath = [[NSBundle mainBundle] executablePath];
		mojoPath = [mojoPath stringByDeletingLastPathComponent];
		mojoPath = [mojoPath stringByDeletingLastPathComponent];
		mojoPath = [mojoPath stringByDeletingLastPathComponent];
		
		return mojoPath;
	}
	else
	{
		// This method is being called from the MojoHelper application
		
		NSString *mojoHelperPath = [[NSBundle mainBundle] executablePath];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		
		// If the mojoHelperPath is inside the Mojo application, we can go up a few directories
		// Otherwise, the MojoHelper application is being run as the active target,
		// and the Mojo application is at the same level as the MojoHelper application.
		
		NSArray *mojoHelperPathComponents = [mojoHelperPath pathComponents];
		if([mojoHelperPathComponents containsObject:@"Mojo.app"])
		{
			NSString *mojoPath = [mojoHelperPath stringByDeletingLastPathComponent];
			mojoPath = [mojoPath stringByDeletingLastPathComponent];
			mojoPath = [mojoPath stringByDeletingLastPathComponent];
			
			return mojoPath;
		}
		else
		{
			NSString *mojoPath = [mojoHelperPath stringByDeletingLastPathComponent];
			mojoPath = [mojoPath stringByAppendingPathComponent:@"Mojo.app"];
			
			return mojoPath;
		}
	}
}

/**
 * Returns the path to the MojoHelper application.
 * This method may be called by either the Mojo or MojoHelper application.
**/
- (NSString *)mojoHelperPath
{
	if([self isMojo])
	{
		// This method is being called from the Mojo application
		
		return [[NSBundle mainBundle] pathForResource:@"MojoHelper" ofType:@"app"];
	}
	else
	{
		// This method is being called from the MojoHelper application
		
		NSString *mojoHelperPath = [[NSBundle mainBundle] executablePath];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		mojoHelperPath = [mojoHelperPath stringByDeletingLastPathComponent];
		
		return mojoHelperPath;
	}
}

@end
