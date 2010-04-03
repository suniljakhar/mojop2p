#import "MojoApp.h"
#import "MojoAppDelegate.h"
#import "MSWController.h"
#import "ServiceListController.h"
#import "BonjourResource.h"
#import "MojoXMPP.h"


@implementation MojoApp

/**
 * This is called via AppleScript commands.
 * Tell application "Mojo" to view library 8J3TPX65EH
**/
- (void)scripterSaysViewLibrary:(NSScriptCommand *)command
{
	NSString *libID = [command directParameter];
	
	if(libID != nil)
	{
		NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
		
		BOOL isAvailableOnNetwork  = [helperProxy bonjourClient_isLibraryAvailable:libID];
		BOOL isAvailableOnInternet = [helperProxy xmpp_isLibraryAvailable:libID];
		
		if(isAvailableOnNetwork)
		{
			// Loop through all the open windows, and see if any of them are the one we want...
			NSArray *windows = [NSApp windows];
			
			NSUInteger i;
			for(i = 0; i < [windows count]; i++)
			{
				NSWindow *currentWindow = [windows objectAtIndex:i];
				
				if([[currentWindow windowController] isKindOfClass:[MSWController class]])
				{
					MSWController *currentWC = [currentWindow windowController];
					
					if([currentWC isLocalResource] && [[currentWC libraryID] isEqual:libID])
					{
						[currentWindow makeKeyAndOrderFront:self];
						return;
					}
				}
			}
			
			// Get the local user for the corresponding library ID
			BonjourResource *bonjourResource = [helperProxy bonjourClient_resourceForLibraryID:libID];
			
			// Create Manual Sync Window
			MSWController *temp = [[MSWController alloc] initWithLocalResource:bonjourResource];
			[temp showWindow:self];
			
			// Note: MSWController will automatically release itself when the user closes the window
			
			// Activate our application and bring it to the front
			[NSApp activateIgnoringOtherApps:YES];
		}
		else if(isAvailableOnInternet)
		{
			// Loop through all the open windows, and see if any of them are the one we want...
			NSArray *windows = [NSApp windows];
			
			NSUInteger i;
			for(i = 0; i < [windows count]; i++)
			{
				NSWindow *currentWindow = [windows objectAtIndex:i];
				
				if([[currentWindow windowController] isKindOfClass:[MSWController class]])
				{
					MSWController *currentWC = [currentWindow windowController];
					
					if([currentWC isRemoteResource] && [[currentWC libraryID] isEqual:libID])
					{
						[currentWindow makeKeyAndOrderFront:self];
						return;
					}
				}
			}
			
			// Get remote user for the corresponding library ID
			XMPPUserAndMojoResource *xmppUserResource = [helperProxy xmpp_userAndMojoResourceForLibraryID:libID];
			
			// Create Manual Sync Window
			MSWController *temp = [[MSWController alloc] initWithRemoteResource:xmppUserResource];
			[temp showWindow:self];
			
			// Note: MSWController will automatically release itself when the user closes the window
			
			// Activate our application and bring it to the front
			[NSApp activateIgnoringOtherApps:YES];
		}
	}
}

/**
 * This is called via AppleScript commands.
 * Tell application "Mojo" to view preferences
**/
- (void)scripterSaysViewPreferences:(NSScriptCommand *)command
{
	[NSApp activateIgnoringOtherApps:YES];
	[preferencesWindow makeKeyAndOrderFront:self];
}

@end
