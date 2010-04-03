#import "MenuController.h"
#import "MojoDefinitions.h"
#import "BonjourClient.h"
#import "BonjourResource.h"
#import "MojoXMPPClient.h"
#import "XMPPUser.h"
#import "XMPPResource.h"


// Declare private methods
@interface MenuController (PrivateAPI)
- (void)updateMenuItems:(NSNotification *)note;
@end


@implementation MenuController

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if((self = [super init]))
	{
		// Register for notifications
		
		// The BonjourClient posts 3 different notifications:
		// DidFindLocalServiceNotification, DidUpdateLocalServiceNotification, DidRemoveLocalServiceNotification
		// 
		// We need to know almost every change to the roster...
//		[[NSNotificationCenter defaultCenter] addObserver:self
//												 selector:@selector(updateMenuItems:)
//													 name:DidFindLocalServiceNotification
//												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(updateMenuItems:)
													 name:DidUpdateLocalServiceNotification
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(updateMenuItems:)
													 name:DidRemoveLocalServiceNotification
												   object:nil];
		
		// The MojoXMPPClient uses multicast delegates instead of notifications
		// We add ourselves as a delegate source in the awakeFromNib method
	}
	return self;
}

- (void)dealloc
{	
	NSLog(@"Destroying %@", self);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[statusItem release];
	[super dealloc];
}

// AWAKE FROM NIB
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
	[[MojoXMPPClient sharedInstance] addDelegate:self];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	BOOL isBackgroundHelperEnabled = [defaults boolForKey:PREFS_BACKGROUND_HELPER_ENABLED];
	BOOL shouldDisplayMenuItem     = [defaults boolForKey:PREFS_DISPLAY_MENU_ITEM];
	
	if(isBackgroundHelperEnabled && shouldDisplayMenuItem)
	{
		[self displayMenuItem];
	}
}

// MENU ITEM DISPLAY
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)displayMenuItem
{
	if(statusItem == nil)
	{
		statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
		
		[statusItem setHighlightMode:YES];
		[statusItem setImage:[NSImage imageNamed:@"trayNoteColor.png"]];
		[statusItem setMenu:menu];
		[statusItem setEnabled:YES];
	}
}

- (void)hideMenuItem
{
	if(statusItem != nil)
	{
		[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
		
		[statusItem release];
		statusItem = nil;
	}
}

// INTERFACE BUILDER ACTIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)connect:(id)sender
{
	NSString *libID;
	
	// The represented object of the sender is either a BonjourResource or a XMPPUser.
	id resource = [sender representedObject];
	
	if([resource isKindOfClass:[BonjourResource class]])
	{
		BonjourResource *localResource = (BonjourResource *)resource;
		
		libID = [localResource libraryID];
	}
	else
	{
		XMPPUserAndMojoResource *remoteResource = (XMPPUserAndMojoResource *)resource;
		
		libID = [remoteResource libraryID];
	}
	
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

- (IBAction)openMojo:(id)sender
{
	NSString *command = @"tell application \"Mojo\" to activate";
	
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

/**
 * Called when the user clicks the preferences option.
**/
- (IBAction)preferences:(id)sender
{
	NSString *command = [NSString stringWithFormat:@"tell application \"Mojo\" to view preferences"];
	
	// Note that we don't use NSAppleScript - it doesn't work
	
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

/**
 * Called when the user clicks the quit button.
 * We want to quit Mojo, and then the MojoHelper.
**/
- (IBAction)quit:(id)sender
{
	// We need to tell the Mojo application itself to quit if it's running
	// We could use applescript to do this, but we don't want to launch the application just to tell it to quit
	// So if we used applescript, we'd have to first check to see if it's running...
	// DistributedNotifications are just much easier for this purpose
	
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"Quitting"
																   object:@"MojoHelper"
																 userInfo:nil
													   deliverImmediately:YES];
	
	// And now we can go ahead and exit ourselves
	[NSApp terminate:0];
}

// PRIVATE METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called anytime a service is found, updated, or removed.
**/
- (void)updateMenuItems:(NSNotification *)notification
{
	int i;
	int total = 0;
	
	// Get items in menu
	NSArray *items = [menu itemArray];
	
	// Find out how many items to remove
	for(i = 0; i < [items count]; i++)
	{
		NSMenuItem *item = [items objectAtIndex:i];
		
		if([item action] == @selector(connect:))
		{
			if(total == 0)
				total += 2; /* An extra item to account for the seperator */
			else
				total += 1;
		}
	}
	
	// Remove the items
	for(i = 0; i < total; i++)
	{
		[menu removeItemAtIndex:0];
	}
	
	// Get the local users
	NSMutableArray *localResources = [[BonjourClient sharedInstance] sortedResourcesByNameIncludingLocalhost:NO];
	
	// Get the remote users (only the online ones)
	NSArray *temp = [[MojoXMPPClient sharedInstance] sortedUserAndMojoResources];
	NSMutableArray *remoteUserResources = [[temp mutableCopy] autorelease];
	
	// Remove any remote resources that are also on the local network
	NSMutableDictionary *localResourcesDict = [NSMutableDictionary dictionaryWithCapacity:[localResources count]];
	
	for(i = 0; i < [localResources count]; i++)
	{
		BonjourResource *resource = [localResources objectAtIndex:i];
		NSString *libID = [resource libraryID];
		
		if(libID)
		{
			[localResourcesDict setObject:resource forKey:libID];
		}
	}
	
	for(i = [remoteUserResources count] - 1; i >= 0; i--)
	{
		XMPPUserAndMojoResource *userResource = [remoteUserResources objectAtIndex:i];
		NSString *libID = [userResource libraryID];
		
		if([localResourcesDict objectForKey:libID])
		{
			[remoteUserResources removeObjectAtIndex:i];
		}
	}
	
	// Now merge the two arrays into one
	NSInteger numLocalResources = [localResources count];
	NSInteger numRemoteResources = [remoteUserResources count];
	
	NSMutableArray *allResources = [NSMutableArray arrayWithCapacity:(numLocalResources + numRemoteResources)];
	
	int lrIndex = 0;
	int rrIndex = 0;
	
	while((lrIndex < numLocalResources) || (rrIndex < numRemoteResources))
	{
		BonjourResource *currentLR = nil;
		XMPPUserAndMojoResource *currentRR = nil;
		
		NSString *lrDisplayName = nil;
		NSString *rrDisplayName = nil;
		
		if(lrIndex < numLocalResources)
		{
			currentLR = [localResources objectAtIndex:lrIndex];
			lrDisplayName = [currentLR displayName];
		}
		
		if(rrIndex < numRemoteResources)
		{
			currentRR = [remoteUserResources objectAtIndex:rrIndex];
			rrDisplayName = [currentRR mojoDisplayName];
		}
		
		if(lrDisplayName && !rrDisplayName)
		{
			[allResources addObject:currentLR];
			lrIndex++;
		}
		else if(!lrDisplayName && rrDisplayName)
		{
			[allResources addObject:currentRR];
			rrIndex++;
		}
		else
		{
			if([lrDisplayName compare:rrDisplayName] != NSOrderedDescending)
			{
				[allResources addObject:currentLR];
				lrIndex++;
			}
			else
			{
				[allResources addObject:currentRR];
				rrIndex++;
			}
		}
	}
	
	// Add the seperator if necessary
	if([allResources count] > 0)
	{
		[menu insertItem:[NSMenuItem separatorItem] atIndex:0];
	}
	
	// Add the services
	for(i = [allResources count] - 1; i >= 0; i--)
	{
		id resource = [allResources objectAtIndex:i];
		
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[resource displayName]
													  action:@selector(connect:)
											   keyEquivalent:@""];
		[item autorelease];
		[item setTarget:self];
		[item setRepresentedObject:resource];
		
		[menu insertItem:item atIndex:0];
	}
}

- (void)xmppClientDidUpdateRoster:(XMPPClient *)sender
{
	[self updateMenuItems:nil];
}

- (void)xmppClientDidDisconnect:(XMPPClient *)sender
{
	[self updateMenuItems:nil];
}

@end
