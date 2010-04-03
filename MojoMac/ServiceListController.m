#import "ServiceListController.h"
#import "MojoDefinitions.h"
#import "MojoAppDelegate.h"
#import "LibrarySubscriptions.h"
#import "MSWController.h"
#import "SubscriptionsController.h"
#import "BonjourResource.h"
#import "MojoXMPP.h"
#import "PreferencesController.h"
#import "ServerListManager.h"


@implementation ServiceListController

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	if((self = [super init]))
	{
		// Configure number formatter
		numberFormatter = [[NSNumberFormatter alloc] init];
		[numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
		[numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
		
		// Setup the various font sizes to be used as attributes
		NSFont *largeFont = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		NSFont *smallFont = [NSFont systemFontOfSize:[NSFont systemFontSize]-2];
		
		// Setup the various colors to be used as attributes
		NSColor *whiteColor = [NSColor whiteColor];
		NSColor *grayColor = [NSColor grayColor];
		
		// Set line break attributes
		NSMutableParagraphStyle *paragraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
		[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
				
		// Initialize standard attributes
		largeText = [[NSMutableDictionary alloc] initWithCapacity:1];
		[largeText setObject:largeFont      forKey:NSFontAttributeName];
		[largeText setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		smallText = [[NSMutableDictionary alloc] initWithCapacity:1];
		[smallText setObject:smallFont      forKey:NSFontAttributeName];
		[smallText setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		whiteLargeText = [[NSMutableDictionary alloc] initWithCapacity:2];
		[whiteLargeText setObject:largeFont       forKey:NSFontAttributeName];
		[whiteLargeText setObject:whiteColor      forKey:NSForegroundColorAttributeName];
		[whiteLargeText setObject:paragraphStyle  forKey:NSParagraphStyleAttributeName];
		
		whiteSmallText = [[NSMutableDictionary alloc] initWithCapacity:2];
		[whiteSmallText setObject:smallFont      forKey:NSFontAttributeName];
		[whiteSmallText setObject:whiteColor     forKey:NSForegroundColorAttributeName];
		[whiteSmallText setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		grayLargeText = [[NSMutableDictionary alloc] initWithCapacity:2];
		[grayLargeText setObject:largeFont      forKey:NSFontAttributeName];
		[grayLargeText setObject:grayColor      forKey:NSForegroundColorAttributeName];
		[grayLargeText setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		graySmallText = [[NSMutableDictionary alloc] initWithCapacity:2];
		[graySmallText setObject:smallFont      forKey:NSFontAttributeName];
		[graySmallText setObject:grayColor      forKey:NSForegroundColorAttributeName];
		[graySmallText setObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
		
		// Initialize array of users and subscriptions
		sortedOnlineServices  = [[NSArray alloc] initWithObjects:nil];
		sortedOfflineServices = [[NSArray alloc] initWithObjects:nil];
		
		// Set initial views
		isDisplayingShareName = YES;
		hasUpdatedServerList = NO;
	}
	return self;
}

/**
 * Standard Deconstructor.
**/
- (void)dealloc
{	
	NSLog(@"Destroying %@", self);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[numberFormatter release];
	[largeText release];
	[smallText release];
	[whiteLargeText release];
	[whiteSmallText release];
	[grayLargeText release];
	[graySmallText release];
	[sortedOnlineServices release];
	[sortedOfflineServices release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called automatically via Cocoa after the nib is loaded and ready
**/
- (void)awakeFromNib
{
	// Configure service table
	[serviceTable setDelegate:self];
	[serviceTable setDataSource:self];
	
	// Setup plus button
	[plusButton setImage:[NSImage imageNamed:@"plus.png"]];
	
	// Initially disable the buttons because nothing is initially selected
	// When the selection is changed, the tableViewSelectionDidChange: method will handle it
	[serviceButton setEnabled:NO forSegment:0];
	[serviceButton setEnabled:NO forSegment:1];
	
	// Configure the tooltips for the buttons
	// Unfortunately, we don't seem to be able to do this in Interface Builder
	NSString *toolTip0 = NSLocalizedString(@"Browse Music Library", @"ToolTip for music note button in Service List");
	NSString *toolTip1 = NSLocalizedString(@"Edit Playlist Subscriptions", @"ToolTip for gear button in Service List");
	
	[[serviceButton cell] setToolTip:toolTip0 forSegment:0];
	[[serviceButton cell] setToolTip:toolTip1 forSegment:1];
	
	// Register for notifications
	
	// Bonjour posts 3 different notifications:
	// DidFindLocalServiceNotification, DidUpdateLocalServiceNotification, DidRemoveLocalServiceNotification
	// 
	// We need to know every little change to the roster...
//	[[NSNotificationCenter defaultCenter] addObserver:self
//											 selector:@selector(updateServiceList:)
//												 name:DidFindLocalServiceNotification
//											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateServiceList:)
												 name:DidUpdateLocalServiceNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateServiceList:)
												 name:DidRemoveLocalServiceNotification
											   object:nil];
	
	// Register for XMPP notifications
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateServiceList:)
												 name:DidUpdateRosterNotification
											   object:nil];
	
	// The XMPPClient posts notification within our address space for connection changes
	// We register for these to keep the statusPopup properly configured
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientConnecting:)
												 name:XMPPClientConnectingNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientDidGoOnline:)
												 name:XMPPClientDidGoOnlineNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientDidDisconnect:)
												 name:XMPPClientDidDisconnectNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientAuthFailure:)
												 name:XMPPClientAuthFailureNotification
											   object:nil];
	
	// The SubscriptionsDidChangeNotification is posted by the SubscriptionsController
	// when a user modifies their subscriptions, either by editing the subscriptions, or completely unsubscribing.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateServiceList:)
												 name:SubscriptionsDidChangeNotification
											   object:nil];
	
	// The MojoAppDelegate posts a HelperProxyReadyNotification after the helper proxy is setup
	// This allows us to:
	// 1. Configure the statusPulldown menu based on the xmppClient state
	// 2. Fetch local services
	// 3. Fetch remote services
	// 3. Add subscriptions to the list that are not otherwise present
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(helperProxyReady:)
												 name:HelperProxyReadyNotification
											   object:nil];
	
	// Register for notifications of changes to our account information
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(shareNameDidChange:)
												 name:ShareNameDidChangeNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(jidDidChange:)
												 name:JIDDidChangeNotification
											   object:nil];
	
	// Register for notifications of updates to the server list
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateHostnameField:) 
												 name:DidUpdateServerListNotification
											   object:nil];
}

/**
 * Called (via notifications) whenever the service list needs to be updated.
 * The following notifications may invoke this method:
 * - DidUpdateLocalServiceNotification
 * - DidRemoveLocalServiceNotification
 * - DidUpdateRosterNotification
 * - HelperProxyReadyNotification
 * - SubscriptionsDidChangeNotification
**/
- (void)updateServiceList:(NSNotification *)notification
{
	// Get a reference to the helperProxy as we'll be using it a lot
	NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
	
	// Figure out what is currently selected
	// After we update our list, we want to reselect what is currently selected
	id selectedOnlineService = nil;
	id selectedOfflineService = nil;
	
	int selectedRow = [serviceTable selectedRow];
	if(selectedRow >= 0)
	{
		if(selectedRow < [sortedOnlineServices count])
		{
			int serviceIndex = selectedRow;
			selectedOnlineService = [[[sortedOnlineServices objectAtIndex:serviceIndex] retain] autorelease];
		}
		else
		{
			int serviceIndex = selectedRow - [sortedOnlineServices count];
			selectedOfflineService = [[[sortedOfflineServices objectAtIndex:serviceIndex] retain] autorelease];
		}
	}
	
	// Get the list of local resources
	NSArray *localResources;
	if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_DEMO_MODE])
		localResources = [helperProxy bonjourClient_sortedResourcesByNameIncludingLocalhost:YES];
	else
		localResources = [helperProxy bonjourClient_sortedResourcesByNameIncludingLocalhost:NO];
	
	// Get the list of remote users and resources
	NSMutableArray *remoteUserResources = [[[helperProxy xmpp_sortedUserAndMojoResources] mutableCopy] autorelease];
	NSArray *remoteOfflineUsers = [helperProxy xmpp_sortedUnavailableUsersByName];
	
	// Remove any remote resource that is also available on the local network
	// At the same time, build up a dictionary that will allow us to look for any resource given a libraryID.
	// This dictionary will be used again later to determine if a set of subscriptions has an available resource.
	NSMutableDictionary *resourcesDict = [NSMutableDictionary dictionaryWithCapacity:[localResources count]];
	
	int i;
	for(i = 0; i < [localResources count]; i++)
	{
		BonjourResource *resource = [localResources objectAtIndex:i];
		NSString *libID = [resource libraryID];
		
		if(libID)
		{
			[resourcesDict setObject:resource forKey:libID];
		}
	}
	
	for(i = [remoteUserResources count] - 1; i >= 0; i--)
	{
		XMPPUserAndMojoResource *userResource = [remoteUserResources objectAtIndex:i];
		NSString *libID = [userResource libraryID];
		
		if(libID)
		{
			if([resourcesDict objectForKey:libID])
				[remoteUserResources removeObjectAtIndex:i];
			else
				[resourcesDict setObject:userResource forKey:libID];
		}
	}
	
	// Get list of subscriptions
	NSMutableArray *subscriptions = [helperProxy sortedSubscriptionsByName];
	
	// Now remove from this list any subscriptions that has an available resource (either local or remote)
	// We do this because we don't want to display these users in the list twice
	for(i = [subscriptions count] - 1; i >= 0; i--)
	{
		LibrarySubscriptions *ls = [subscriptions objectAtIndex:i];
		NSString *libID = [ls libraryID];
		
		if(libID)
		{
			if([resourcesDict objectForKey:libID])
			{
				[subscriptions removeObjectAtIndex:i];
			}
		}
	}
	
	// Now sort the localResources and remoteUserResources into a single array
	// This is fairly straightforward, since both are already sorted
	
	NSInteger numLocalResources = [localResources count];
	NSInteger numRemoteResources = [remoteUserResources count];
	
	NSMutableArray *onlineServices = [NSMutableArray arrayWithCapacity:(numLocalResources + numRemoteResources)];
	
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
			[onlineServices addObject:currentLR];
			lrIndex++;
		}
		else if(!lrDisplayName && rrDisplayName)
		{
			[onlineServices addObject:currentRR];
			rrIndex++;
		}
		else
		{
			if([lrDisplayName compare:rrDisplayName] != NSOrderedDescending)
			{
				[onlineServices addObject:currentLR];
				lrIndex++;
			}
			else
			{
				[onlineServices addObject:currentRR];
				rrIndex++;
			}
		}
	}
	
	// Update our cached array of online services
	[sortedOnlineServices release];
	sortedOnlineServices = [onlineServices retain];
	
	// Now sort the remoteOfflineUsers and subscriptions into a single array
	// This is fairly straightforward, since both are already sorted
	
	NSInteger numOfflineUsers = [remoteOfflineUsers count];
	NSInteger numSubscriptions = [subscriptions count];
	
	NSMutableArray *offlineServices = [NSMutableArray arrayWithCapacity:(numOfflineUsers + numSubscriptions)];
	
	int uIndex = 0;
	int sIndex = 0;
	
	while((uIndex < numOfflineUsers) || (sIndex < numSubscriptions))
	{
		XMPPUser *currentU = nil;
		LibrarySubscriptions *currentS = nil;
		
		NSString *uDisplayName = nil;
		NSString *sDisplayName = nil;
		
		if(uIndex < numOfflineUsers)
		{
			currentU = [remoteOfflineUsers objectAtIndex:uIndex];
			uDisplayName = [currentU displayName];
		}
		
		if(sIndex < numSubscriptions)
		{
			currentS = [subscriptions objectAtIndex:sIndex];
			sDisplayName = [currentS displayName];
		}
		
		if(uDisplayName && !sDisplayName)
		{
			[offlineServices addObject:currentU];
			uIndex++;
		}
		else if(!uDisplayName && sDisplayName)
		{
			[offlineServices addObject:currentS];
			sIndex++;
		}
		else
		{
			if([uDisplayName compare:sDisplayName] != NSOrderedDescending)
			{
				[offlineServices addObject:currentU];
				uIndex++;
			}
			else
			{
				[offlineServices addObject:currentS];
				sIndex++;
			}
		}
	}
	
	// Update our cached array of offline users
	
	[sortedOfflineServices release];
	sortedOfflineServices = [offlineServices retain];
	
	// Deselect whatever is selected
	[serviceTable selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
	
	// Notify the table that it needs to reload it's data
	[serviceTable reloadData];
	
	// And now reselect what was previously selected
	if(selectedOnlineService)
	{
		BOOL done = NO;
		for(i = 0; i < [sortedOnlineServices count] && !done; i++)
		{
			if([[sortedOnlineServices objectAtIndex:i] isEqual:selectedOnlineService])
			{
				int rowIndex = i;
				[serviceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
				
				done = YES;
			}
		}
	}
	if(selectedOfflineService)
	{
		BOOL done = NO;
		for(i = 0; i < [sortedOfflineServices count] && selectedOfflineService; i++)
		{
			if([[sortedOfflineServices objectAtIndex:i] isEqual:selectedOfflineService])
			{
				int rowIndex = i + [sortedOnlineServices count];
				[serviceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
				
				done = YES;
			}		
		}
	}
}

/**
 * This method is called when the helperProxy is first ready to be used.
 * We take this opportunity to setup the statusPopup, and update the service list.
**/
- (void)helperProxyReady:(NSNotification *)notification
{
	NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
	
	NSString *shareName = [helperProxy appliedShareName];
	
	NSString *jid = [helperProxy XMPPUsername];
	
	if(isDisplayingShareName || !jid)
	{
		isDisplayingShareName = YES;
		[shareNameOrJIDField setStringValue:shareName];
	}
	else
	{
		isDisplayingShareName = NO;
		[shareNameOrJIDField setStringValue:jid];
	}
	
	int xmppClientState = [helperProxy xmpp_connectionState];
	
	if(xmppClientState == NSOffState)
	{
		NSString *localizedStr = NSLocalizedString(@"Unavailable", @"Availability status in roster");
		
		[statusPulldown setTitle:localizedStr];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOnState];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSOffState];
	}
	else if(xmppClientState == NSMixedState)
	{
		NSString *localizedStr = NSLocalizedString(@"Connecting", @"Availability status in roster");
		
		[statusPulldown setTitle:localizedStr];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOffState];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSMixedState];
	}
	else
	{
		NSString *localizedStr = NSLocalizedString(@"Available", @"Availability status in roster");
		
		[statusPulldown setTitle:localizedStr];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOffState];
		[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSOnState];
		
		[plusButton setEnabled:YES];
	}
	
	// Regardless of the xmppClientState, we still want to call updateServiceList
	// because we also want to get the list of subscriptions
	[self updateServiceList:notification];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Local Services:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)browseMusic
{
	int selectedRow = [serviceTable selectedRow];
	
	if((selectedRow >= 0) && (selectedRow < [sortedOnlineServices count]))
	{
		// Get the service that is selected in the table
		int index = selectedRow;
		id service = [sortedOnlineServices objectAtIndex:index];
		
		if([service isMemberOfClass:[BonjourResource class]])
		{
			BonjourResource *bonjourResource = (BonjourResource *)service;
			NSString *libID = [bonjourResource libraryID];
			
			// Loop through all the open windows, and see if any of them are the one we want...
			NSArray *windows = [NSApp windows];
			
			int i;
			for(i = 0; i < [windows count]; i++)
			{
				NSWindow *currentWindow = [windows objectAtIndex:i];
				MSWController *currentWC = [currentWindow windowController];
				
				if([currentWC isLocalResource] && [[currentWC libraryID] isEqual:libID])
				{
					[currentWindow makeKeyAndOrderFront:self];
					return;
				}
			}
			
			// Create Manual Sync Window
			MSWController *temp = [[MSWController alloc] initWithLocalResource:bonjourResource];
			[temp showWindow:self];
			
			// Note: MSWController will automatically release itself when the user closes the window
		}
		else
		{
			XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
			NSString *libID = [xmppUserResource libraryID];
			
			// Loop through all the open windows, and see if any of them are the one we want...
			NSArray *windows = [NSApp windows];
			
			int i;
			for(i = 0; i < [windows count]; i++)
			{
				NSWindow *currentWindow = [windows objectAtIndex:i];
				MSWController *currentWC = [currentWindow windowController];
				
				if([currentWC isRemoteResource] && [[currentWC libraryID] isEqual:libID])
				{
					[currentWindow makeKeyAndOrderFront:self];
					return;
				}
			}
			
			// Create Manual Sync Window
			MSWController *temp = [[MSWController alloc] initWithRemoteResource:xmppUserResource];
			[temp showWindow:self];
			
			// Note: MSWController will automatically release itself when the user closes the window
		}
	}
}

- (void)editSubscriptions
{
	int selectedRow = [serviceTable selectedRow];
	
	// Ignore command if nothing is selected
	if(selectedRow < 0) return;
	
	// Get the service object that's selected
	id service;
	if(selectedRow < [sortedOnlineServices count])
	{
		int index = selectedRow;
		service = [sortedOnlineServices objectAtIndex:index];
	}
	else
	{
		int index = selectedRow - [sortedOnlineServices count];
		service = [sortedOfflineServices objectAtIndex:index];
	}
	
	// Now decide what to do based on what type of service is selected
	
	if([service isMemberOfClass:[BonjourResource class]])
	{
		BonjourResource *bonjourResource = (BonjourResource *)service;
		
		SubscriptionsController *temp;
		temp = [[SubscriptionsController alloc] initWithDockingWindow:serviceListWindow];
		[temp editSubscriptionsForLocalResource:bonjourResource];
		
		// Note: SubscriptionsController is an independent NSWindowController in a seperate nib file
		// It will automatically release itself when the user closes the sheet
	}
	else if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
	{
		XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
		
		SubscriptionsController *temp;
		temp = [[SubscriptionsController alloc] initWithDockingWindow:serviceListWindow];
		[temp editSubscriptionsForRemoteResource:xmppUserResource];
		
		// Note: SubscriptionsController is an independent NSWindowController in a seperate nib file
		// It will automatically release itself when the user closes the sheet
	}
	else
	{
		LibrarySubscriptions *ls = service;
		
		SubscriptionsController *temp;
		temp = [[SubscriptionsController alloc] initWithDockingWindow:serviceListWindow];
		[temp editSubscriptionsForLibraryID:[ls libraryID]];
		
		// Note: SubscriptionsController is an independent NSWindowController in a seperate nib file
		// It will automatically release itself when the user closes the sheet
	}
}

- (IBAction)didClickServiceButton:(id)sender
{
	if([sender selectedSegment] == 0)
	{
		[self browseMusic];
	}
	else
	{
		[self editSubscriptions];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Roster Menu:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Here's how menu items work:
 * Each menu item has a specified action.
 * If the first responder (eg key window) responds to that specified action, the menu item can become enabled.
 * It will be automatically enabled, unless the first responder has the validateMenuItem: method.
 * In this case, the menu item will only be enabled if the validateMenuItem: method says it can be.
 * 
 * We take advantage of this to only enable the "Remove Buddy" item if an internet buddy is selected.
**/
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(getInfo:))
	{
		int selectedRow = [serviceTable selectedRow];
		
		return (selectedRow >= 0);
	}
	else if([menuItem action] == @selector(addBuddy:))
	{
		return [plusButton isEnabled];
	}
	else if([menuItem action] == @selector(removeBuddy:))
	{
		int selectedRow = [serviceTable selectedRow];
		
		if(selectedRow < 0) return NO;
		
		id service;
		if(selectedRow < [sortedOnlineServices count])
		{
			int index = selectedRow;
			service = [sortedOnlineServices objectAtIndex:index];
		}
		else
		{
			int index = selectedRow - [sortedOnlineServices count];
			service = [sortedOfflineServices objectAtIndex:index];
		}
		
		if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
		{
			XMPPUserAndMojoResource *umr = (XMPPUserAndMojoResource *)service;
			
			XMPPJID *jid = [[[[umr resource] jid] retain] autorelease];
			
			XMPPJID *myJID = [[[NSApp delegate] helperProxy] xmpp_myJID];
			
			if([[myJID bare] isEqualToString:[jid bare]])
			{
				// No, you shouldn't remove yourself
				return NO;
			}
			else
			{
				return YES;
			}
		}
		else if([service isMemberOfClass:[XMPPUser class]])
		{
			return YES;
		}
		
		return NO;
	}
	return YES;
}

- (IBAction)accountError_ok:(id)sender
{
	// Close the sheet
	[accountErrorSheet orderOut:self];
	[NSApp endSheet:accountErrorSheet];
	
	// Display accounts section
	[[[NSApp delegate] preferencesController] showAccountsSection];
}

- (IBAction)authError_ok:(id)sender
{
	// Close the sheet
	[authErrorSheet orderOut:self];
	[NSApp endSheet:authErrorSheet];
	
	// Display accounts section
	[[[NSApp delegate] preferencesController] showAccountsSection];
}

- (IBAction)getInfo:(id)sender
{
	int selectedRow = [serviceTable selectedRow];
	
	if(selectedRow < 0) return;
	
	id service;
	if(selectedRow < [sortedOnlineServices count])
	{
		int index = selectedRow;
		service = [sortedOnlineServices objectAtIndex:index];
	}
	else
	{
		int index = selectedRow - [sortedOnlineServices count];
		service = [sortedOfflineServices objectAtIndex:index];
	}
	
	// Reset everything
	[getInfoNameField setEnabled:YES];
	[getInfoOkButton setEnabled:YES];
	
	// Update name field
	[getInfoNameField setStringValue:[service displayName]];
	
	// Update bonjour and jabber fields
	
	if([service isMemberOfClass:[BonjourResource class]])
	{
		BonjourResource *bonjourResource = (BonjourResource *)service;
		
		[getInfoBonjourField setStringValue:[bonjourResource name]];
		
		NSString *libID = [service libraryID];
		
		NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
		
		XMPPUserAndMojoResource *xmppUserResource = [helperProxy xmpp_userAndMojoResourceForLibraryID:libID];
		
		if(xmppUserResource)
			[getInfoJabberField setStringValue:[[[xmppUserResource user] jid] bare]];
		else
			[getInfoJabberField setStringValue:@""];
	}
	else if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
	{
		XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
		
		NSString *jidStr = [[[xmppUserResource user] jid] bare];
		
		[getInfoJabberField setStringValue:jidStr];
		[getInfoBonjourField setStringValue:@""];
		
		NSString *myJidStr = [[[[NSApp delegate] helperProxy] xmpp_myJID] bare];
		
		if([jidStr isEqualToString:myJidStr])
		{
			// Weird things happen when you try to modify your own account
			
			[getInfoNameField setEnabled:NO];
			[getInfoOkButton setEnabled:NO];
		}
	}
	else if([service isMemberOfClass:[XMPPUser class]])
	{
		XMPPUser *xmppUser = (XMPPUser *)service;
		
		NSString *jidStr = [[xmppUser jid] bare];
		
		[getInfoJabberField setStringValue:jidStr];
		[getInfoBonjourField setStringValue:@""];
	}
	else
	{
		// How did this happen?
		return;
	}
	
	// Display the sheet
	[NSApp beginSheet:getInfoSheet
	   modalForWindow:serviceListWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
}

- (IBAction)getInfo_cancel:(id)sender
{
	// Close the sheet
	[getInfoSheet orderOut:self];
	[NSApp endSheet:getInfoSheet];
}

- (IBAction)getInfo_ok:(id)sender
{
	// Close the sheet
	[getInfoSheet orderOut:self];
	[NSApp endSheet:getInfoSheet];
	
	// Update the display names of any users
	// Note that we do this AFTER we close the sheet, because if the sheet is still open,
	// the GUI (service list table) won't be properly updated when it receives updates notifications
	
	int selectedRow = [serviceTable selectedRow];
	
	if(selectedRow < 0) return;
	
	id service;
	if(selectedRow < [sortedOnlineServices count])
	{
		int index = selectedRow;
		service = [[[sortedOnlineServices objectAtIndex:index] retain] autorelease];
	}
	else
	{
		int index = selectedRow - [sortedOnlineServices count];
		service = [[[sortedOfflineServices objectAtIndex:index] retain] autorelease];
	}
	
	// Note, we seem to require the retain-autorelease statement in Leopard
	// Apparently objectAtIndex just returns a simple references, and doesn't retain-autorelease for us
	
	// Update the name for the selected service
	NSString *updatedNickname = [getInfoNameField stringValue];
	
	NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
	
	if([service isMemberOfClass:[BonjourResource class]])
	{
		BonjourResource *bonjourResource = (BonjourResource *)service;
		NSString *libID = [bonjourResource libraryID];
		
		[helperProxy bonjourClient_setNickname:updatedNickname forLibraryID:libID];
		
		XMPPUserAndMojoResource *xmppUserResource = [helperProxy xmpp_userAndMojoResourceForLibraryID:libID];
		
		if(xmppUserResource)
		{
			[helperProxy xmpp_setNickname:updatedNickname forBuddy:[[xmppUserResource user] jid]];
		}
	}
	else if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
	{
		XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
		
		[helperProxy xmpp_setNickname:updatedNickname forBuddy:[[xmppUserResource user] jid]];
	}
	else if([service isMemberOfClass:[XMPPUser class]])
	{
		XMPPUser *xmppUser = (XMPPUser *)service;
		
		[helperProxy xmpp_setNickname:updatedNickname forBuddy:[xmppUser jid]];
	}
}

- (void)updateHostnameField:(NSNotification *)notification
{
	NSXMLDocument *doc = nil;
	
	NSData *data = [[NSData alloc] initWithContentsOfFile:[ServerListManager serverListPath]];
	if(data)
	{
		doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
	}
	
	if(doc)
	{
		NSArray *allServers = [[doc rootElement] children];
		
		if([allServers count] > 0)
		{
			[addBuddyHostnameField removeAllItems];
			
			NSUInteger i;
			for(i = 0; i < [allServers count]; i++)
			{
				NSXMLElement *server = [allServers objectAtIndex:i];
				
				NSString *serverName = [[server attributeForName:@"name"] stringValue];
				
				[addBuddyHostnameField addItemWithObjectValue:serverName];
			}
			
		}
	}
	
	[doc release];
	[data release];
	
	hasUpdatedServerList = YES;
}

- (IBAction)addBuddy:(id)sender
{
	// Reset everything
	[addBuddyUsernameField setStringValue:@""];
	[addBuddyHostnameField setStringValue:@""];
	[addBuddyNicknameField setStringValue:@""];
	
	[addBuddySheet makeFirstResponder:addBuddyUsernameField];
	
	if([ServerListManager serverListNeedsUpdate])
	{
		[ServerListManager updateServerList];
	}
	else if(!hasUpdatedServerList)
	{
		[self updateHostnameField:nil];
	}
	
	// Display the sheet
	[NSApp beginSheet:addBuddySheet
	   modalForWindow:serviceListWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
}

- (IBAction)addBuddy_cancel:(id)sender
{
	// Close the sheet
	[addBuddySheet orderOut:self];
	[NSApp endSheet:addBuddySheet];
}

- (IBAction)addBuddy_ok:(id)sender
{
	// We need to send a request similar to the following:
	// 
	// <iq type="set">
	//   <query xmlns="jabber:iq:roster">
	//     <item jid="username@hostname"></item>
	//   </query>
	// </iq>
	
	NSString *username = [addBuddyUsernameField stringValue];
	NSString *hostname = [addBuddyHostnameField stringValue];
	NSString *nickname = [addBuddyNicknameField stringValue];
	
	// Create JID from username and hostname
	XMPPJID *jid = [XMPPJID jidWithUser:username domain:hostname resource:nil];
	
	if(jid == nil || [jid user] == nil)
	{
		[addBuddyErrorField setHidden:NO];
		return;
	}
	
	// Close the sheet
	[addBuddySheet orderOut:self];
	[NSApp endSheet:addBuddySheet];
	
	// Allow the XMPPClient to handle all underlying stream issues involved with adding a user
	// Note that we do this AFTER we close the sheet, because if the sheet is still open,
	// the GUI (service list table) won't be properly updated when it receives it's notification
	[[[NSApp delegate] helperProxy] xmpp_addBuddy:jid withNickname:nickname];
}

- (IBAction)removeBuddy:(id)sender
{
	int selectedRow = [serviceTable selectedRow];
	
	id service;
	if(selectedRow < [sortedOnlineServices count])
	{
		int index = selectedRow;
		service = [sortedOnlineServices objectAtIndex:index];
	}
	else
	{
		int index = selectedRow - [sortedOnlineServices count];
		service = [sortedOfflineServices objectAtIndex:index];
	}
	
	if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
	{
		XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
		
		XMPPJID *jid = [[xmppUserResource user] jid];
		
		[[[NSApp delegate] helperProxy] xmpp_removeBuddy:jid];
	}
	else if([service isMemberOfClass:[XMPPUser class]])
	{
		XMPPUser *xmppUser = (XMPPUser *)service;
		
		XMPPJID *jid = [xmppUser jid];
		
		[[[NSApp delegate] helperProxy] xmpp_removeBuddy:jid];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPClient Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)shareNameOrJIDClicked:(id)sender
{
	// We want to find out if the user clicked directly on the text
	// Or if it was just a click somewhere else on the button that we can ignore
	
	// Get the location and size of the button
	NSRect viewRect = [sender bounds];
	
	// Get the size of the title
	NSSize cellSize = [[sender cell] cellSize];
	
	NSRect textRect = NSMakeRect(viewRect.origin.x, viewRect.origin.y, cellSize.width, cellSize.height);
	
	// Get the location within the button that the user clicked
	NSPoint locationInWindow = [[NSApp currentEvent] locationInWindow];
	NSPoint locationInButton = [sender convertPoint:locationInWindow fromView:nil];
	
	if(NSPointInRect(locationInButton, textRect))
	{
		NSDistantObject<HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
		
		NSString *shareName = [helperProxy appliedShareName];
		
		NSString *jid = [helperProxy XMPPUsername];
		
		if(isDisplayingShareName && jid)
		{
			isDisplayingShareName = NO;
			[shareNameOrJIDField setStringValue:jid];
			
		}
		else
		{
			isDisplayingShareName = YES;
			[shareNameOrJIDField setStringValue:shareName];
		}
	}
}

- (void)shareNameDidChange:(NSNotification *)notification
{
	if(isDisplayingShareName)
	{
		NSString *shareName = [[[NSApp delegate] helperProxy] appliedShareName];
		
		if(shareName)
		{
			[shareNameOrJIDField setStringValue:shareName];
		}
	}
}

- (void)jidDidChange:(NSNotification *)notification
{
	if(!isDisplayingShareName)
	{
		NSString *jid = [[[NSApp delegate] helperProxy] XMPPUsername];
		
		if(jid)
		{
			[shareNameOrJIDField setStringValue:jid];
		}
	}
}

- (IBAction)changeStatus:(id)sender
{
	NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
	
	if([[sender selectedItem] tag] == 2)
	{
		// The user selected "Available"
		
		if([helperProxy xmpp_connectionState] == NSOffState)
		{
			if([helperProxy xmpp_isMissingAccountInformation])
			{
				// Display the sheet
				[NSApp beginSheet:accountErrorSheet
				   modalForWindow:serviceListWindow
					modalDelegate:self
				   didEndSelector:nil
					  contextInfo:nil];
			}
			else
			{
				[helperProxy xmpp_start];
			}
		}
	}
	else
	{
		// The user selected "Unavailable"
		
		if([helperProxy xmpp_connectionState] != NSOffState)
		{
			[helperProxy xmpp_stop];
		}
	}
}

- (void)xmppClientConnecting:(XMPPClient *)sender
{
	NSString *localizedStr = NSLocalizedString(@"Connecting", @"Availability status in roster");
	
	[statusPulldown setTitle:localizedStr];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOffState];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSMixedState];
}

- (void)xmppClientDidGoOnline:(NSNotification *)notification
{
	NSString *localizedStr = NSLocalizedString(@"Available", @"Availability status in roster");
	
	[statusPulldown setTitle:localizedStr];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOffState];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSOnState];
	
	[plusButton setEnabled:YES];
}

- (void)xmppClientDidDisconnect:(XMPPClient *)sender
{
	NSString *localizedStr = NSLocalizedString(@"Unavailable", @"Availability status in roster");
	
	[statusPulldown setTitle:localizedStr];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:1]] setState:NSOnState];
	[[statusPulldown itemAtIndex:[statusPulldown indexOfItemWithTag:2]] setState:NSOffState];
	
	[plusButton setEnabled:NO];
	
	// We also want to flush the roster
	[self updateServiceList:nil];
}

- (void)xmppClientAuthFailure:(NSNotification *)notification
{
	// Display the sheet
	[NSApp beginSheet:authErrorSheet
	   modalForWindow:serviceListWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Direct Connections:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)didClickOpenURL:(id)sender
{
	// Configure internet URL field
	NSString *placeholder = NSLocalizedString(@"Enter address of remote library", @"URL field placeholder");
	[[internetURLField cell] setPlaceholderString:placeholder];
	
	NSArray *recentURLs = [[NSUserDefaults standardUserDefaults] arrayForKey:PREFS_RECENT_URLS];
	if(recentURLs != nil)
	{
		[internetURLField removeAllItems];
		[internetURLField addItemsWithObjectValues:recentURLs];
	}
	
	// Setup invalid URL warning
	[invalidURLField setHidden:YES];
	
	// Setup IP placeholder
	[myIPField setStringValue:NSLocalizedString(@"Fetching IP address...", @"Placeholder in www sheet")];
	
	// Display the registration sheet
	[NSApp beginSheet:internetSheet
	   modalForWindow:serviceListWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
	
	// Fork off background thread to obtain and display the external IP address of the user
	[NSThread detachNewThreadSelector:@selector(fetchIPThread:) toTarget:self withObject:nil];
}

- (void)fetchIPFinished:(NSString *)myIP
{
	int serverPort = [[[NSApp delegate] helperProxy] currentServerPortNumber];

	// Todo: Implement support for TLS
//	if([[[NSApp delegate] helperProxy] requiresTLS])
//		[myIPField setStringValue:[NSString stringWithFormat:@"https://%@:%i", myIP, serverPort]];
//	else
		[myIPField setStringValue:[NSString stringWithFormat:@"http://%@:%i", myIP, serverPort]];
	
	[myIPField setTextColor:[NSColor blackColor]];
}

- (void)fetchIPThread:(id)ignore
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSURL *myIPURL = [NSURL URLWithString:@"http://deusty.com/utilities/getMyIP.php"];
	
	NSStringEncoding encoding;
	NSString *myIP = [NSString stringWithContentsOfURL:myIPURL usedEncoding:&encoding error:NULL];
	
	[self performSelectorOnMainThread:@selector(fetchIPFinished:) withObject:myIP waitUntilDone:YES];
	
	[pool release];
}

- (IBAction)internet_learnMore:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_SCREENCASTS]];
}

- (IBAction)internet_cancel:(id)sender
{
	[internetSheet orderOut:self];
	[NSApp endSheet:internetSheet];
}

- (IBAction)internet_ok:(id)sender
{
	// Remove any leading/trailing whitespace
	// This prevents users from having problems with accidental whitespace
	NSMutableString *aRemotePath = [[[internetURLField stringValue] mutableCopy] autorelease];
	CFStringTrimWhitespace((CFMutableStringRef)aRemotePath);
	
	// Convert input to a URL
	NSURL *url = [NSURL URLWithString:aRemotePath];
	
	// Check for valid URL
	if(!url || ![url scheme] || ![url host] || ![url port])
	{
		[invalidURLField setHidden:NO];
		return;
	}
	
	// Extract just what we need in the proper format
	NSString *remotePath = [NSString stringWithFormat:@"%@://%@:%i", [url scheme], [url host], [[url port] intValue]];
	NSURL *remoteURL = [NSURL URLWithString:remotePath];
	
	// Update the text field so that it's perfect next time they view the sheet
	[internetURLField setStringValue:remotePath];
	
	// Close the sheet	
	[internetSheet orderOut:self];
	[NSApp endSheet:internetSheet];
	
	// Bring up the iTunes browser
	MSWController *temp = [[MSWController alloc] initWithRemoteURL:remoteURL];
	[temp showWindow:self];
	
	// Store the entered URL in the recent list
	NSArray *recentURLs = [[NSUserDefaults standardUserDefaults] arrayForKey:PREFS_RECENT_URLS];
	if(recentURLs == nil)
	{
		recentURLs = [NSArray arrayWithObject:remotePath];
		
		[[NSUserDefaults standardUserDefaults] setObject:recentURLs forKey:PREFS_RECENT_URLS];
	}
	else
	{
		NSMutableArray *mRecentURLs = [[recentURLs mutableCopy] autorelease];
		
		[mRecentURLs removeObject:remotePath];
		[mRecentURLs insertObject:remotePath atIndex:0];
		
		if([mRecentURLs count] > 5)
		{
			[mRecentURLs removeObjectsInRange:NSMakeRange(5, [mRecentURLs count]-5)];
		}
		
		[[NSUserDefaults standardUserDefaults] setObject:mRecentURLs forKey:PREFS_RECENT_URLS];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSTableView DataSource Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	int totalCount = [sortedOnlineServices count] + [sortedOfflineServices count];
	
	if(totalCount == 0)
	{
		// We are going to display 1 row in the table
		// It will just some text saying something like "No Mojo Services Available"
		return 1;
	}
	
	return totalCount;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	int totalCount = [sortedOnlineServices count] + [sortedOfflineServices count];
	
	// If there are no services or subscriptions to display
	if(totalCount == 0)
	{
		// There are no services available, so this must be the single message row
		if([[column identifier] isEqualToString:@"image"])
			return nil;
		else
		{
			NSString *localizedStr = NSLocalizedString(@"No Mojo Services Available", @"Empty Service List");
			return [[[NSAttributedString alloc] initWithString:localizedStr attributes:grayLargeText] autorelease];
		}
	}
	
	id service;
	if(rowIndex < [sortedOnlineServices count])
	{
		int serviceIndex = rowIndex;
		service = [[[sortedOnlineServices objectAtIndex:serviceIndex] retain] autorelease];
	}
	else
	{
		int serviceIndex = rowIndex - [sortedOnlineServices count];
		service = [[[sortedOfflineServices objectAtIndex:serviceIndex] retain] autorelease];
	}
	
	BOOL isRowSelected = [tableView isRowSelected:rowIndex];
	BOOL isFirstResponder = [[[tableView window] firstResponder] isEqual:tableView];
	BOOL isKeyWindow = [[tableView window] isKeyWindow];
	BOOL isApplicationActive = [NSApp isActive];
	
	BOOL isRowHighlighted = (isRowSelected && isFirstResponder && isKeyWindow && isApplicationActive);
	
	if([service isMemberOfClass:[BonjourResource class]])
	{
		BonjourResource *bonjourResource = (BonjourResource *)service;
		
		if([[column identifier] isEqualToString:@"image"])
		{
			if([bonjourResource requiresPassword])
				return [NSImage imageNamed:@"onlineLocalMusicP.png"];
			else
				return [NSImage imageNamed:@"onlineLocalMusic.png"];
		}
		else
		{
			NSString *displayName = [bonjourResource displayName];
			if(!displayName)
			{
				displayName = @"";
			}
			
			// If this service is our service, add the little (me) token to it
			NSDistantObject <HelperProtocol> *helperProxy = [[NSApp delegate] helperProxy];
			
			if([[helperProxy bonjourClient_localhostServiceName] isEqualToString:[bonjourResource name]])
			{
				NSString *localizedStr = NSLocalizedString(@" (me)", @"Appended to users own service name");
				displayName = [displayName stringByAppendingString:localizedStr];
			}
			
			int songCount = [bonjourResource numSongs];
			
			if(songCount <= 0)
			{
				NSAttributedString *result;
				
				if(isRowHighlighted)
					result = [[NSAttributedString alloc] initWithString:displayName attributes:whiteLargeText];
				else
					result = [[NSAttributedString alloc] initWithString:displayName attributes:largeText];
				
				
				return [result autorelease];
			}
			else
			{
				NSString *songCountStr;
				if(songCount == 1)
				{
					NSString *localized = NSLocalizedString(@"1 Song", @"Row info in service list table");
					songCountStr = localized;
				}
				else
				{
					NSString *localized = NSLocalizedString(@"%@ Songs", @"Row info in service list table");
					NSString *formatted = [numberFormatter stringFromNumber:[NSNumber numberWithInt:songCount]];
					songCountStr = [NSString stringWithFormat:localized, formatted];
				}
				
				NSAttributedString *line1, *line2, *lineBr;
				
				if(isRowHighlighted)
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:whiteLargeText] autorelease];
				}
				else
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:largeText] autorelease];
				}
				
				lineBr = [[[NSAttributedString alloc] initWithString:@"\n"] autorelease];
				
				if(isRowHighlighted)
				{
					line2  = [[[NSAttributedString alloc] initWithString:songCountStr
															  attributes:whiteSmallText] autorelease];
				}
				else
				{
					line2  = [[[NSAttributedString alloc] initWithString:songCountStr
															  attributes:graySmallText] autorelease];
				}
				
				NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithAttributedString:line1];
				[mas appendAttributedString:lineBr];
				[mas appendAttributedString:line2];
				
				return [mas autorelease];
			}
		}
	}
	else if([service isMemberOfClass:[XMPPUserAndMojoResource class]])
	{
		XMPPUserAndMojoResource *xmppUserResource = (XMPPUserAndMojoResource *)service;
		
		if([[column identifier] isEqualToString:@"image"])
		{
			if([xmppUserResource requiresPassword])
				return [NSImage imageNamed:@"onlineRemoteMusicP.png"];
			else
				return [NSImage imageNamed:@"onlineRemoteMusic.png"];
		}
		else
		{
			NSString *displayName = [xmppUserResource mojoDisplayName];
			if(!displayName)
			{
				displayName = @"";
			}
			
			int songCount = [xmppUserResource numSongs];
			
			if(songCount <= 0)
			{
				NSAttributedString *result;
				
				if(isRowHighlighted)
					result = [[NSAttributedString alloc] initWithString:displayName attributes:whiteLargeText];
				else
					result = [[NSAttributedString alloc] initWithString:displayName attributes:largeText];
				
				return [result autorelease];
			}
			else
			{
				NSString *songCountStr;
				if(songCount == 1)
				{
					NSString *localized = NSLocalizedString(@"1 Song", @"Row info in service list table");
					songCountStr = localized;
				}
				else
				{
					NSString *localized = NSLocalizedString(@"%@ Songs", @"Row info in service list table");
					NSString *formatted = [numberFormatter stringFromNumber:[NSNumber numberWithInt:songCount]];
					songCountStr = [NSString stringWithFormat:localized, formatted];
				}
				
				NSAttributedString *line1, *line2, *lineBr;
				
				if(isRowHighlighted)
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:whiteLargeText] autorelease];
				}
				else
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:largeText] autorelease];
				}
				
				lineBr = [[[NSAttributedString alloc] initWithString:@"\n"] autorelease];
				
				if(isRowHighlighted)
				{
					line2  = [[[NSAttributedString alloc] initWithString:songCountStr
															  attributes:whiteSmallText] autorelease];
				}
				else
				{
					line2  = [[[NSAttributedString alloc] initWithString:songCountStr
															  attributes:graySmallText] autorelease];
				}
				
				NSMutableAttributedString *mas;
				mas = [[NSMutableAttributedString alloc] initWithAttributedString:line1];
				[mas appendAttributedString:lineBr];
				[mas appendAttributedString:line2];
				
				return [mas autorelease];
			}
		}
	}
	else if([service isMemberOfClass:[XMPPUser class]])
	{
		XMPPUser *xmppUser = (XMPPUser *)service;
		
		if([[column identifier] isEqualToString:@"image"])
		{
			return [NSImage imageNamed:@"offlineMusic.png"];
		}
		else
		{
			NSString *displayName = [xmppUser displayName];
			if(!displayName)
			{
				displayName = @"";
			}
			
			if([xmppUser isPendingApproval])
			{
				NSAttributedString *line1, *line2, *lineBr;
				
				if(isRowHighlighted)
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:whiteLargeText] autorelease];
				}
				else
				{
					line1  = [[[NSAttributedString alloc] initWithString:displayName
															  attributes:largeText] autorelease];
				}
				
				lineBr = [[[NSAttributedString alloc] initWithString:@"\n"] autorelease];
				
				NSString *localized = NSLocalizedString(@"Pending approval", @"Row info in service list table");
				
				if(isRowHighlighted)
				{
					line2  = [[[NSAttributedString alloc] initWithString:localized
															  attributes:whiteSmallText] autorelease];
				}
				else
				{
					line2  = [[[NSAttributedString alloc] initWithString:localized
															  attributes:graySmallText] autorelease];
				}
				
				NSMutableAttributedString *mas;
				mas = [[NSMutableAttributedString alloc] initWithAttributedString:line1];
				[mas appendAttributedString:lineBr];
				[mas appendAttributedString:line2];
				
				return [mas autorelease];
			}
			else
			{
				NSAttributedString *result;
				
				if(isRowHighlighted)
					result = [[NSAttributedString alloc] initWithString:displayName attributes:whiteLargeText];
				else
					result = [[NSAttributedString alloc] initWithString:displayName attributes:largeText];
				
				return [result autorelease];
			}
		}
	}
	else
	{
		LibrarySubscriptions *ls = service;
		
		if([[column identifier] isEqualToString:@"image"])
		{
			return [NSImage imageNamed:@"offlineMusic.png"];
		}
		else
		{
			int playlistCount = [ls numberOfSubscribedPlaylists];
			
			NSString *playlisCountStr;
			if(playlistCount == 1)
			{
				NSString *localized = NSLocalizedString(@"1 Playlist Subscription", @"Row info in service list table");
				playlisCountStr = localized;
			}
			else
			{
				NSString *localized = NSLocalizedString(@"%@ Playlist Subscriptions", @"Row info in service list table");
				NSString *formatted = [numberFormatter stringFromNumber:[NSNumber numberWithInt:playlistCount]];
				playlisCountStr = [NSString stringWithFormat:localized, formatted];
			}
			
			NSAttributedString *line1, *line2, *lineBr;
			
			if(isRowHighlighted)
			{
				line1 = [[[NSAttributedString alloc] initWithString:[ls displayName]
														 attributes:whiteLargeText] autorelease];
			}
			else
			{
				line1 = [[[NSAttributedString alloc] initWithString:[ls displayName]
														 attributes:largeText] autorelease];
			}
			
			lineBr = [[[NSAttributedString alloc] initWithString:@"\n"] autorelease];
			
			if(isRowHighlighted)
			{
				line2  = [[[NSAttributedString alloc] initWithString:playlisCountStr
														  attributes:whiteSmallText] autorelease];
			}
			else
			{
				line2  = [[[NSAttributedString alloc] initWithString:playlisCountStr
														  attributes:graySmallText] autorelease];
			}
			
			NSMutableAttributedString *mas;
			mas = [[NSMutableAttributedString alloc] initWithAttributedString:line1];
			[mas appendAttributedString:lineBr];
			[mas appendAttributedString:line2];
			
			return [mas autorelease];
		}
	}
}

/**
 * NSTableView delegate method.
 * The delegate can implement this method to disallow selection of particular rows.
**/
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(int)rowIndex
{
	int totalCount = [sortedOnlineServices count] + [sortedOfflineServices count];
	
	if(totalCount == 0)
	{
		// The only row is the message row saying there are no services available
		// Don't allow the user to select this row.
		return NO;
	}
	
	return YES;
}

/**
 * NSTableView delegate method.
 * The delegate can implement this method to disallow editing of specific cells.
**/
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	// The user has double-clicked on a row in the table
	// If the user is online, we want the default action to be browsing their music
	// Otherwise the only thing to do is to edit their subscriptions
	
	int selectedRow = [serviceTable selectedRow];
	
	if(selectedRow >= 0)
	{
		if(selectedRow < [sortedOnlineServices count])
		{
			[self browseMusic];
		}
		else
		{
			[self editSubscriptions];
		}
	}
	
	return NO;
}

/**
 * Called when the selection in the table changes.
 * We use this hook to update the segmented control buttons.
**/
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	int selectedRow = [serviceTable selectedRow];
	
	if(selectedRow >= 0)
	{
		if(selectedRow < [sortedOnlineServices count])
		{
			[serviceButton setEnabled:YES forSegment:0];
		//	[serviceButton setEnabled:YES forSegment:1];
		}
		else
		{
			[serviceButton setEnabled:NO  forSegment:0];
		//	[serviceButton setEnabled:YES forSegment:1];
		}
	}
	else
	{
		[serviceButton setEnabled:NO forSegment:0];
		[serviceButton setEnabled:NO forSegment:1];
	}
}

@end
