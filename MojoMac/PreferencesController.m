#import "PreferencesController.h"
#import "MojoDefinitions.h"
#import "MojoAppDelegate.h"
#import "ITunesLocalSharedData.h"
#import "RHKeychain.h"
#import "WelcomeController.h"
#import "XMPPJID.h"

@interface PreferencesController (PrivateAPI)
- (void)switchViews:(NSToolbarItem *)item;
- (void)updateSharingInfo:(NSTimer *)aTimer;
@end


@implementation PreferencesController

/**
 * Called via Cocoa when the nib file has been loaded, and the GUI connections are in place.
 * This is the proper place to setup all of our GUI controls.
**/
- (void)awakeFromNib
{
	// Initialize items dictionary
	// This will hold all the toolbar items
	items = [[NSMutableDictionary alloc] init];
    
	// Create all toolbar items and add them to our items dictionary
	
    NSToolbarItem *item1 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"General"] autorelease];
    [item1 setLabel:NSLocalizedString(@"General", @"Preference Pane Option")];
    [item1 setImage:[NSImage imageNamed:@"General.png"]];
    [item1 setTarget:self];
    [item1 setAction:@selector(switchViews:)];
	
	NSToolbarItem *item2 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Accounts"] autorelease];
    [item2 setLabel:NSLocalizedString(@"Accounts", @"Preference Pane Option")];
    [item2 setImage:[NSImage imageNamed:@"Accounts.tiff"]];
    [item2 setTarget:self];
    [item2 setAction:@selector(switchViews:)];
	
	NSToolbarItem *item3 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"iTunes"] autorelease];
    [item3 setLabel:NSLocalizedString(@"iTunes", @"Preference Pane Option")];
    [item3 setImage:[NSImage imageNamed:@"iTunes.png"]];
    [item3 setTarget:self];
    [item3 setAction:@selector(switchViews:)];
	
	NSToolbarItem *item4 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Sharing"] autorelease];
    [item4 setLabel:NSLocalizedString(@"Sharing", @"Preference Pane Option")];
    [item4 setImage:[NSImage imageNamed:@"Sharing.png"]];
    [item4 setTarget:self];
    [item4 setAction:@selector(switchViews:)];
	
	NSToolbarItem *item5 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Advanced"] autorelease];
    [item5 setLabel:NSLocalizedString(@"Advanced", @"Preference Pane Option")];
    [item5 setImage:[NSImage imageNamed:@"Advanced.png"]];
    [item5 setTarget:self];
    [item5 setAction:@selector(switchViews:)];
	
	NSToolbarItem *item6 = [[[NSToolbarItem alloc] initWithItemIdentifier:@"Software Update"] autorelease];
    [item6 setLabel:NSLocalizedString(@"Software Update", @"Preference Pane Option")];
    [item6 setImage:[NSImage imageNamed:@"SoftwareUpdate.png"]];
    [item6 setTarget:self];
    [item6 setAction:@selector(switchViews:)];
	
	[items setObject:item1 forKey:[item1 itemIdentifier]];
	[items setObject:item2 forKey:[item2 itemIdentifier]];
	[items setObject:item3 forKey:[item3 itemIdentifier]];
	[items setObject:item4 forKey:[item4 itemIdentifier]];
	[items setObject:item5 forKey:[item5 itemIdentifier]];
	[items setObject:item6 forKey:[item6 itemIdentifier]];
	
    // Any other items you want to add, do so here.
    // After you are done, just do all the toolbar stuff.
	
    toolbar = [[[NSToolbar alloc] initWithIdentifier:@"PreferencePanes"] autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    
	[preferencesWindow setToolbar:toolbar];
	[preferencesWindow setShowsToolbarButton:NO];
	
	// Setup all controls that are for Mojo, and not MojoHelper
	[playlistMatrix selectCellWithTag:[[NSUserDefaults standardUserDefaults] integerForKey:PREFS_PLAYLIST_OPTION]];
	
	// We need to update the isXMPPClientDisconnected variable
	// This variable will properly enable/disable all GUI elements in the accounts section
	// But, in order for binding to work properly we need to either
	// a) call willChangeValueForKey before and didChangeValueForKey after changing the value
	// b) use key-value coding to update the value
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"isXMPPClientDisconnected"];
	
	shouldRefreshITunesInfo = YES;
	isPlaylistsPopupReady = NO;
	isPlaylistsTableReady = NO;
	
	// Now we can't setup the controls for MojoHelper until we have a DO connection to MojoHelper
	// So we register for the notification that tells us when the helperProxy is ready
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(helperProxyReady:)
												 name:HelperProxyReadyNotification
											   object:nil];
	
	// We also would like to be notified when the helper proxy closes,
	// so we can be sure to save any changes that we're in the process of making
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(helperProxyClosing:)
												 name:HelperProxyClosingNotification
											   object:nil];
	
	// Also register for any notifications that will change preferences
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didCreateXMPPAccount)
												 name:DidCreateXMPPAccountNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientIsActive:)
												 name:XMPPClientConnectingNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientIsActive:)
												 name:XMPPClientDidConnectNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(xmppClientIsUnactive:)
												 name:XMPPClientDidDisconnectNotification
											   object:nil];
	
	// And finally, switch to the default view
	[self switchViews:nil];
	
	// Don't center the window til after we've switched the view, or else it will center that small window stub
	[preferencesWindow center];
}

/**
 * This method is called (via notifications) when the helper proxy is setup and ready.
 * This allows us to setup our preferences items that correlate to preferences in the helper app.
**/
- (void)helperProxyReady:(NSNotification *)notification
{
	id <HelperProtocol> helperProxy = [[NSApp delegate] helperProxy];
	
	// 
	// General preferences
	// 
	
	[shareNameField setStringValue:[helperProxy shareName]];
	
	BOOL requiresPassword = [helperProxy requiresPassword];
	[requirePasswordButton setState:requiresPassword ? NSOnState : NSOffState];
	[passwordField setEnabled:requiresPassword];
	if(requiresPassword)
	{
		NSString *password = [RHKeychain passwordForHTTPServer];
		if(password) {
			[passwordField setStringValue:password];
		}
	}
	
//	[requireTLSButton setEnabled:requiresPassword];
//	[requireTLSButton setState:[helperProxy requiresTLS] ? NSOnState : NSOffState];
	
	[enableHelperAppButton setState:[helperProxy isBackgroundHelperEnabled] ? NSOnState : NSOffState];
	[launchAtLoginButton setState:[helperProxy shouldLaunchAtLogin] ? NSOnState : NSOffState];
	[showMenuItemButton setState:[helperProxy shouldDisplayMenuItem] ? NSOnState : NSOffState];
	
	if([helperProxy isBackgroundHelperEnabled] == NO)
	{
		[launchAtLoginButton setEnabled:NO];
		[showMenuItemButton setEnabled:NO];
	}
	
	[updateIntervalPopup selectItemWithTag:[helperProxy updateIntervalInMinutes]];
	
	// 
	// Accounts preferences
	// 
	
	[autoLoginButton setState:[helperProxy isXMPPAutoLoginEnabled] ? NSOnState : NSOffState];
	
	NSString *xmppUsername = [helperProxy XMPPUsername];
	NSString *xmppPassword = [RHKeychain passwordForXMPPServer];
	if(xmppUsername) {
		[xmppUsernameField setStringValue:xmppUsername];
	}
	if(xmppPassword) {
		[xmppPasswordField setStringValue:xmppPassword];
	}
	
	if(!xmppUsername || [xmppUsername isEqualToString:@""] || !xmppPassword || [xmppPassword isEqualToString:@""])
		[createNewAccountButton setHidden:NO];
	else
		[createNewAccountButton setHidden:YES];
	
	[xmppServerField setStringValue:[helperProxy XMPPServer]];
	[xmppPortField setIntValue:[helperProxy XMPPPort]];
	
	BOOL useSSL = [helperProxy XMPPServerUsesSSL];
	[xmppUseSSLButton setState:useSSL ? NSOnState : NSOffState];
	
	BOOL allowSSC = [helperProxy allowSelfSignedCertificate];
	[xmppAllowSSCButton setState:allowSSC ? NSOnState : NSOffState];
	
	BOOL allowMismatch = [helperProxy allowSSLHostNameMismatch];
	[xmppAllowMismatchButton setState:allowMismatch ? NSOnState : NSOffState];
	
	NSString *xmppResource = [helperProxy XMPPResource];
	if(xmppResource) {
		[xmppResourceField setStringValue:xmppResource];
	}
	
	// We need to update the isXMPPClientDisconnected variable
	// This variable will properly enable/disable all GUI elements in the accounts section
	// But, in order for binding to work properly, we need to either
	// a) call willChangeValueForKey before and didChangeValueForKey after changing the value
	// b) use key-value coding to update the value
	BOOL newValue = [helperProxy xmpp_connectionState] == NSOffState;
	[self setValue:[NSNumber numberWithBool:newValue] forKey:@"isXMPPClientDisconnected"];
	
	// 
	// iTunes preferences
	// 
	
	BOOL addFromSubscriptions = [helperProxy playlistOption] != PLAYLIST_OPTION_NONE;
	[addFromSubscriptionsButton setState:addFromSubscriptions ? NSOnState : NSOffState];
	
	NSString *iTunesLocation = [helperProxy iTunesLocation];
	if(iTunesLocation)
	{
		[iTunesLocationField setStringValue:iTunesLocation];
	}
	
	// 
	// Sharing preferences
	// 
	
	BOOL isSharingFilterEnabled = [helperProxy isSharingFilterEnabled];
	[sharingMatrix selectCellAtRow:(isSharingFilterEnabled ? 1 : 0) column:0];
	
	[sharingTable setEnabled:isSharingFilterEnabled];
	
	// 
	// Advanced preferences
	// 
	
	int serverPortNumber = [helperProxy defaultServerPortNumber];
	if(serverPortNumber > 0)
	{
		[serverPortField setIntValue:serverPortNumber];
	}
	
	[stuntFeedbackButton setState:[helperProxy sendStuntFeedback] ? NSOnState : NSOffState];
}

/**
 * This method is called (via notifications) when the helper proxy is closing.
 * Generally, this means the application is also closing too.
**/
- (void)helperProxyClosing:(NSNotification *)notification
{
	if(updateSharingInfoTimer)
	{
		[self updateSharingInfo:updateSharingInfoTimer];
	}
}

/**
 * This method is called everytime a toolbar item is clicked.
 * If item is nil, switch to the default toolbar item ("General")
**/
- (void)switchViews:(NSToolbarItem *)item
{
    NSString *sender;
    if(item == nil)
	{
		sender = @"General";
		[toolbar setSelectedItemIdentifier:sender];
		item = [items objectForKey:sender];
    }
	else
	{
        sender = [item itemIdentifier];
    }
	
    // Make a temp pointer.
    NSView *prefsView;
	
    //set the title to the name of the Preference Item.
    [preferencesWindow setTitle:[item label]];
	
	if([sender isEqualToString:@"General"]) {
		prefsView = generalView;
	}
	else if([sender isEqualToString:@"Accounts"]) {
		prefsView = accountsView;
	}
	else if([sender isEqualToString:@"iTunes"]) {
		prefsView = iTunesView;
	}
	else if([sender isEqualToString:@"Sharing"]) {
		prefsView = sharingView;
	}
	else if([sender isEqualToString:@"Advanced"]) {
		prefsView = advancedView;
	}
	else if([sender isEqualToString:@"Software Update"]) {
		prefsView = softwareUpdateView;
	}
    
	// To stop flicker, we make a temp blank view.
	NSView *tempView = [[NSView alloc] initWithFrame:[[preferencesWindow contentView] frame]];
	[preferencesWindow setContentView:tempView];
	[tempView release];
    
	// Mojo to get the right frame for the new window.
	NSRect pv_frame = [prefsView frame];
	NSRect pw_frame = [preferencesWindow frame];
	NSRect pw_cv_frame = [[preferencesWindow contentView] frame];
	
	NSRect newFrame = pw_frame;
	newFrame.size.height = pv_frame.size.height + (pw_frame.size.height - pw_cv_frame.size.height);
	newFrame.size.width = pv_frame.size.width;
	newFrame.origin.y += (pw_cv_frame.size.height - pv_frame.size.height);
	
	// Set the frame to newFrame and animate it. (change animate:YES to animate:NO if you don't want this)
	[preferencesWindow setFrame:newFrame display:YES animate:YES];
	
	// Set the main content view to the new view we have picked through the if structure above.
	[preferencesWindow setContentView:prefsView];
}

- (void)showAccountsSection
{
	NSToolbarItem *item = [items objectForKey:@"Accounts"];
	
	[toolbar setSelectedItemIdentifier:[item itemIdentifier]];
	[self switchViews:item];
	[preferencesWindow makeKeyAndOrderFront:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSWindow delegate methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
	if(shouldRefreshITunesInfo)
	{
		shouldRefreshITunesInfo = NO;
		
		[playlistsPopup setEnabled:NO];
		[playlistsField setEnabled:NO];
		
		[sharingTable setEnabled:NO];
		[sharingTable setDataSource:nil];
		[sharingTable setDelegate:nil];
		
		[NSThread detachNewThreadSelector:@selector(refreshITunesInfoThread:) toTarget:self withObject:nil];
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	shouldRefreshITunesInfo = YES;
	isPlaylistsPopupReady = NO;
	isPlaylistsTableReady = NO;
	
	[playlistsPopup setEnabled:NO];
	[playlistsField setEnabled:NO];
	
	[sharingTable setEnabled:NO];
	[sharingTable setDataSource:nil];
	[sharingTable setDelegate:nil];
	
	if(updateSharingInfoTimer)
	{
		[self updateSharingInfo:updateSharingInfoTimer];
	}
	
	[data release];
	data = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Parsing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Background thread method to parse iTunes library.
 *
 * This method is run in a separate thread.
 * It parses the iTunes music library in a background thread, allowing the GUI to remain responsive.
 * After the parsing is complete, it sets up the playlistsPopup component and playlists table.
**/
- (void)refreshITunesInfoThread:(id)obj
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSAssert(data == nil, @"Leaking memory! ITunesLocalSharedData should be nil!");
	
	data = [[ITunesLocalSharedData sharedLocalITunesData] retain];
	
	[self performSelectorOnMainThread:@selector(updatePlaylistsPopup) withObject:nil waitUntilDone:YES];
	[self performSelectorOnMainThread:@selector(updatePlaylistsTable) withObject:nil waitUntilDone:YES];
	
    [pool release];
}

- (void)updatePlaylistsPopup
{
	// Clear the current contents of the popup
	[playlistsPopup removeAllItems];
	
	NSMenuItem *defaultItem = [[[NSMenuItem alloc] init] autorelease];
	[defaultItem setTitle:@"Mojo"];
	[defaultItem setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
	[defaultItem setTag:-1];
	
	[[playlistsPopup menu] addItem:defaultItem];
	[[playlistsPopup menu] addItem:[NSMenuItem separatorItem]];
	
	// Setup the playlist popup component
	NSArray *playlists = [data playlists];
	
	int i;
	for(i = 0; i < [playlists count]; i++)
	{
		NSDictionary *currentPlaylist = [playlists objectAtIndex:i];
		
		if([[currentPlaylist objectForKey:PLAYLIST_TYPE] intValue] == PLAYLIST_TYPE_NORMAL)
		{
			if(![[currentPlaylist objectForKey:PLAYLIST_NAME] isEqualToString:[defaultItem title]])
			{
				NSMenuItem *temp = [[[NSMenuItem alloc] init] autorelease];
				[temp setTitle:[currentPlaylist objectForKey:PLAYLIST_NAME]];
				[temp setImage:[NSImage imageNamed:@"iTunesPlaylist.png"]];
				[temp setTag:i];
				
				// iTunes can actually have multiple playlists with the same name
				// So don't add the item directly to the popup, or it will throw a fit if it finds equally named items
				// Instead, to get around this problem, add all the items directly to the popup's menu
				[[playlistsPopup menu] addItem:temp];
			}
		}
	}
	
	// Add option for a different playlist
	NSMenuItem *otherItem = [[[NSMenuItem alloc] init] autorelease];
	[otherItem setTitle:NSLocalizedString(@"Other...", @"Option to create new playlist in Preferences:iTunes")];
	[otherItem setTag:-2];
	
	[[playlistsPopup menu] addItem:[NSMenuItem separatorItem]];
	[[playlistsPopup menu] addItem:otherItem];
	
	// Now we have the playlists popup setup
	// We need to select the correct playlist, or if the playlist doesn't exist in the list, display the text field
	NSString *playlistName = [[NSUserDefaults standardUserDefaults] objectForKey:PREFS_PLAYLIST_NAME];
	NSMenuItem *item = [playlistsPopup itemWithTitle:playlistName];
	
	if(item)
	{
		// Select the proper playlist in the list
		[playlistsPopup selectItem:item];
	}
	else
	{
		// The playlist doesn't exist yet, so display the text field instead with the name in it
		[playlistsPopup setHidden:YES];
		[playlistsField setHidden:NO];
		[playlistsField setStringValue:playlistName];
	}
	
	// Enable the popup and text field, but only if the user is opting to use a playlist
	BOOL isStandardPlaylistOption = [playlistMatrix selectedTag] == 2;
	
	[playlistsPopup setEnabled:isStandardPlaylistOption];
	[playlistsField setEnabled:isStandardPlaylistOption];
	
	isPlaylistsPopupReady = YES;
}

- (void)updatePlaylistsTable
{
	BOOL isSharingFilterEnabled = [[[NSApp delegate] helperProxy] isSharingFilterEnabled];
	
	[sharingTable setEnabled:isSharingFilterEnabled];
	[sharingTable setDelegate:self];
	[sharingTable setDataSource:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Toolbar delegate methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	 itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
    return [items objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar
{
    return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar
{
	// Make sure we arrange the identifiers in the correct order
	return [NSArray arrayWithObjects:@"General",@"Accounts",@"iTunes",@"Sharing",@"Advanced",@"Software Update",nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
    // Make all of them selectable. This puts that little grey outline thing around an item when you select it.
    return [items allKeys];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)shareNameDidChange:(id)sender
{
	// Remove any leading/trailing whitespace
	// This prevents users from having a name with only whitespace (generally by accident)
	NSMutableString *newShareName = [[[sender stringValue] mutableCopy] autorelease];
	CFStringTrimWhitespace((CFMutableStringRef)newShareName);
	
	[sender setStringValue:newShareName];
	[[[NSApp delegate] helperProxy] setShareName:newShareName];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:ShareNameDidChangeNotification object:self];
}

- (IBAction)toggleRequirePassword:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setRequiresPassword:flag];
	
	// Enable or disable the password field accordingly
	[passwordField setEnabled:flag];
	if(flag)
	{
		[preferencesWindow makeFirstResponder:passwordField];
	}
	
	// It makes no sense to have secure connections enabled if there's no password protection
//	[requireTLSButton setEnabled:flag];
//	if(flag)
//	{
//		if([requireTLSButton state] == NSOnState)
//		{
//			[[[NSApp delegate] helperProxy] setRequiresTLS:YES];
//		}
//	}
//	else
//	{
//		[[[NSApp delegate] helperProxy] setRequiresTLS:NO];
//	}
}

- (IBAction)passwordDidChange:(id)sender
{
	[RHKeychain setPasswordForHTTPServer:[sender stringValue]];
	[[[NSApp delegate] helperProxy] passwordDidChange];
}

- (IBAction)toggleRequireTLS:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setRequiresTLS:flag];
}

- (IBAction)toggleEnableHelperApp:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	
	// Enable or disable the other checkboxes based on this ones status
	[launchAtLoginButton setEnabled:flag];
	[showMenuItemButton  setEnabled:flag];
	
	[[[NSApp delegate] helperProxy] setIsBackgroundHelperEnabled:flag];
}

- (IBAction)toggleLaunchAtLogin:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setShouldLaunchAtLogin:flag];
}

- (IBAction)toggleShowMenuItem:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setShouldDisplayMenuItem:flag];
}

- (IBAction)updateIntervalDidChange:(id)sender
{
	// The update interval is the tag of the selected item (in minutes)
	int updateIntervalInMinutes = [[sender selectedItem] tag];
	[[[NSApp delegate] helperProxy] setUpdateIntervalInMinutes:updateIntervalInMinutes];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accounts Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)createNewAccount:(id)sender
{
	// Create Welcome Window
	WelcomeController *temp = [[WelcomeController alloc] init];
	[temp showWindow:self];
	
	// Note: WelcomeController will automatically release itself when the user closes the window
}

- (IBAction)goToAnswers:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_ACCOUNT_GUIDE]];
}

- (IBAction)toggleXMPPAutoLogin:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setIsXMPPAutoLoginEnabled:flag];
}

- (IBAction)changeXMPPUsername:(id)sender
{
	NSString *username = [sender stringValue];
	
	if(([username length] > 0) && ([username rangeOfString:@"@"].location == NSNotFound))
	{
		NSString *domain = [xmppServerField stringValue];
		if([domain length] == 0)
		{
			domain = @"deusty.com";
		}
		
		[sender setStringValue:[username stringByAppendingFormat:@"@%@", domain]];
	}
	
	[[[NSApp delegate] helperProxy] setXMPPUsername:[sender stringValue]];
	
	// Display/Hide the create new account button as needed
	NSString *xmppUsername = [xmppUsernameField stringValue];
	NSString *xmppPassword = [xmppPasswordField stringValue];
	
	if(!xmppUsername || [xmppUsername isEqualToString:@""] || !xmppPassword || [xmppPassword isEqualToString:@""])
		[createNewAccountButton setHidden:NO];
	else
		[createNewAccountButton setHidden:YES];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:JIDDidChangeNotification object:self];
}

- (IBAction)changeXMPPPassword:(id)sender
{
	[RHKeychain setPasswordForXMPPServer:[sender stringValue]];
	
	// Display/Hide the create new account button as needed
	NSString *xmppUsername = [xmppUsernameField stringValue];
	NSString *xmppPassword = [xmppPasswordField stringValue];
	
	if(!xmppUsername || [xmppUsername isEqualToString:@""] || !xmppPassword || [xmppPassword isEqualToString:@""])
		[createNewAccountButton setHidden:NO];
	else
		[createNewAccountButton setHidden:YES];
}

- (IBAction)changeXMPPServer:(id)sender
{
	[[[NSApp delegate] helperProxy] setXMPPServer:[sender stringValue]];
}

- (IBAction)changeXMPPPort:(id)sender
{
	int newPort = [sender intValue];
	if(newPort < 1 || newPort > 65535) newPort = 5222;
	
	[sender setIntValue:newPort];
	[[[NSApp delegate] helperProxy] setXMPPPort:newPort];
}

- (IBAction)toggleXMPPUseSSL:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setXMPPServerUsesSSL:flag];
}

- (IBAction)toggleXMPPAllowSelfSignedCertificates:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setAllowsSelfSignedCertificate:flag];
}

- (IBAction)toggleXMPPAllowSSLHostNameMismatch:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	[[[NSApp delegate] helperProxy] setAllowsSSLHostNameMismatch:flag];
}

- (IBAction)changeXMPPResource:(id)sender
{
	[[[NSApp delegate] helperProxy] setXMPPResource:[sender stringValue]];
}

- (IBAction)revertToDefaultXMPPSettings:(id)sender
{
	XMPPJID *jid = [XMPPJID jidWithString:[xmppUsernameField stringValue]];
	NSString *domain = [jid domain];
	
	if(domain)
	{
		[xmppServerField setStringValue:domain];
		[xmppServerField sendAction:[xmppServerField action] to:[xmppServerField target]];
	}
	
	[xmppPortField setStringValue:@"5222"];
	[xmppPortField sendAction:[xmppPortField action] to:[xmppPortField target]];
	
	[xmppUseSSLButton setState:NSOffState];
	[xmppUseSSLButton sendAction:[xmppUseSSLButton action] to:[xmppUseSSLButton target]];
	
	[xmppAllowSSCButton setState:NSOffState];
	[xmppAllowSSCButton sendAction:[xmppAllowSSCButton action] to:[xmppAllowSSCButton target]];
	
	[xmppAllowMismatchButton setState:NSOffState];
	[xmppAllowMismatchButton sendAction:[xmppAllowMismatchButton action] to:[xmppAllowMismatchButton target]];
	
	[xmppResourceField setStringValue:@""];
	[xmppResourceField sendAction:[xmppResourceField action] to:[xmppResourceField target]];
}

- (void)didCreateXMPPAccount
{
	id <HelperProtocol> helperProxy = [[NSApp delegate] helperProxy];
	
	NSString *xmppServer = [helperProxy XMPPServer];
	if(xmppServer)
	{
		[xmppServerField setStringValue:xmppServer];
	}
	
	NSString *xmppUsername = [helperProxy XMPPUsername];
	if(xmppUsername)
	{
		[xmppUsernameField setStringValue:xmppUsername];
	}
	
	NSString *xmppPassword = [RHKeychain passwordForXMPPServer];
	if(xmppPassword)
	{
		[xmppPasswordField setStringValue:xmppPassword];
	}
	
	if(!xmppUsername || [xmppUsername isEqualToString:@""] || !xmppPassword || [xmppPassword isEqualToString:@""])
		[createNewAccountButton setHidden:NO];
	else
		[createNewAccountButton setHidden:YES];
}

- (void)xmppClientIsActive:(NSNotification *)notification
{
	// We need to update the isXMPPClientDisconnected variable
	// This variable will properly enable/disable all GUI elements in the accounts section
	// But, in order for binding to work properly we need to either
	// a) call willChangeValueForKey before and didChangeValueForKey after changing the value
	// b) use key-value coding to update the value
	[self setValue:[NSNumber numberWithBool:NO] forKey:@"isXMPPClientDisconnected"];

	// [self willChangeValueForKey:@"isXMPPClientDisconnected"];
	// isXMPPClientDisconnected = NO;
	// [self didChangeValueForKey:@"isXMPPClientDisconnected"];
	
	// Why is this here???
	// [createNewAccountButton setHidden:YES];
}

- (void)xmppClientIsUnactive:(NSNotification *)notification
{
	// We need to update the isXMPPClientDisconnected variable
	// This variable will properly enable/disable all GUI elements in the accounts section
	// But, in order for binding to work properly we need to either
	// a) call willChangeValueForKey before and didChangeValueForKey after changing the value
	// b) use key-value coding to update the value
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"isXMPPClientDisconnected"];
	
	// [self willChangeValueForKey:@"isXMPPClientDisconnected"];
	// isXMPPClientDisconnected = YES;
	// [self didChangeValueForKey:@"isXMPPClientDisconnected"];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)playlistMatrixDidChange:(id)sender
{
	// Store the new playlist option into the user defaults system
	[[NSUserDefaults standardUserDefaults] setInteger:[sender selectedTag] forKey:PREFS_PLAYLIST_OPTION];
	
	// Also update the playlist option for the helper if needed
	if([addFromSubscriptionsButton state] == NSOnState)
	{
		[[[NSApp delegate] helperProxy] setPlaylistOption:[sender selectedTag]];
	}
	
	// Properly enable or disable the standard playlist options
	BOOL isStandardPlaylistOption = ([sender selectedTag] == 2);
	
	[playlistsPopup setEnabled:(isStandardPlaylistOption && isPlaylistsPopupReady)];
	[playlistsField setEnabled:(isStandardPlaylistOption && isPlaylistsPopupReady)];
}

/**
 * Called when the user modifies the name of the playlist in the playlistsField text field.
**/
- (IBAction)changePlaylistName:(id)sender
{
	NSString *playlistName = [sender stringValue];
	
	if([playlistName isEqualToString:@""])
	{
		// The user didn't actually type in a playlist name - default to the original
		playlistName = @"Mojo";
	}
	
	NSMenuItem *item = [playlistsPopup itemWithTitle:playlistName];
	if(item != nil)
	{
		// The user typed in the name of an existing playlist
		// Switch back to viewing the list of playlists, and select the playlist they just typed in
		[playlistsField setHidden:YES];
		[playlistsPopup setHidden:NO];
		[playlistsPopup selectItem:item];
	}
	
	// Save the playlist name to the user defaults system
	[[NSUserDefaults standardUserDefaults] setObject:playlistName forKey:PREFS_PLAYLIST_NAME];
	
	// Also save the playlist name to the user defaults system in the helper app
	[[[NSApp delegate] helperProxy] setPlaylistName:playlistName];
}

/**
 * Called when the selection of the playlist popup is changed.
**/
- (IBAction)changePlaylistSelection:(id)sender
{
	// The default playlist ("Mojo") has a tag of -1
	// All standard playlists have a positive tag
	// The "Other..." option has a tag of -2
	
	if([[sender selectedItem] tag] > -2)
	{
		// The user selected a standard playlist, or the default playlist
		// Save the name to the user defaults system
		NSString *playlistName = [[sender selectedItem] title];
		[[NSUserDefaults standardUserDefaults] setObject:playlistName forKey:PREFS_PLAYLIST_NAME];
		
		// Also save the name to the user defaults system in the helper app
		[[[NSApp delegate] helperProxy] setPlaylistName:playlistName];
	}
	else
	{
		// The user selected the "Other..." option
		// We need to hide the playlistsPopup, and show the playlistsField
		[playlistsPopup setHidden:YES];
		[playlistsField setHidden:NO];
		
		// For some reason, if we make the playlistsField the first responder,
		// and it has some text in it, it will immediately fire.
		// This causes the changePlaylistName: method to be called, which just displays the playlist again...
		if([[playlistsField stringValue] isEqualToString:@""])
		{
			[preferencesWindow makeFirstResponder:playlistsField];
		}
	}
}

/**
 * Called when the user toggles the "Also add downloaded songs from subscriptions" option.
 * 
 * IMPORTANT NOTE: The mojo and mojo helper app both have the same preferences for playlist options.
 * Namely, PREFS_PLAYLIST_OPTION and PREFS_PLAYLIST_NAME.  However, both of them affect each app individually.
 * So if the mojo app is set to use playlist folders, the helper app can be configured to not use anything.
**/
- (IBAction)toggleAddFromSubscriptions:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	
	if(flag)
	{
		// We need the playlistOption for the helper app to match the playlist option for the mojo app
		int playlistOption = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_PLAYLIST_OPTION];
		[[[NSApp delegate] helperProxy] setPlaylistOption:playlistOption];
	}
	else
	{
		[[[NSApp delegate] helperProxy] setPlaylistOption:PLAYLIST_OPTION_NONE];
	}
}

- (IBAction)changeITunesLocation:(id)sender
{
	NSString *filepath = [iTunesLocationField stringValue];
	
	if([filepath length] == 0)
	{
		// Automatic detection
		[iTunesLocationField setTextColor:[NSColor blackColor]];
		[[[NSApp delegate] helperProxy] setITunesLocation:filepath];
		[[[NSApp delegate] helperProxy] forceUpdateITunesInfo];
	}
	else if(![[NSFileManager defaultManager] fileExistsAtPath:filepath])
	{
		// File doesn't exist
		[iTunesLocationField setTextColor:[NSColor redColor]];
	}
	else if(![[filepath pathExtension] isEqualToString:@"xml"])
	{
		// Not an XML file
		[iTunesLocationField setTextColor:[NSColor redColor]];
	}
	else
	{
		// File looks good
		[iTunesLocationField setTextColor:[NSColor blackColor]];
		[[[NSApp delegate] helperProxy] setITunesLocation:filepath];
		[[[NSApp delegate] helperProxy] forceUpdateITunesInfo];
	}
}

- (IBAction)selectITunesLocation:(id)sender
{
	// "Standard" open file panel
	NSArray *fileTypes = [NSArray arrayWithObject:@"xml"];
	
	// Create the File Open Panel class.
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	
	[openPanel setCanChooseDirectories:NO];
	[openPanel setCanChooseFiles:YES];
	[openPanel setCanCreateDirectories:NO];
	[openPanel setAllowsMultipleSelection:NO];
	
	NSString *filepath = [iTunesLocationField stringValue];
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:filepath])
	{
		filepath = [ITunesData localITunesMusicLibraryXMLPath];
	}
	
	if([[NSFileManager defaultManager] fileExistsAtPath:filepath])
	{
		[openPanel beginSheetForDirectory:[filepath stringByDeletingLastPathComponent]
									 file:[filepath lastPathComponent]
									types:fileTypes
						   modalForWindow:preferencesWindow
							modalDelegate:self
						   didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
							  contextInfo:nil];
	}
	else
	{
		[openPanel beginSheetForDirectory:nil
									 file:nil
									types:fileTypes
						   modalForWindow:preferencesWindow
							modalDelegate:self
						   didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
							  contextInfo:nil];
	}
}

- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	// Return code will be NSCancelButton or NSOKButton
	
	if(returnCode == NSOKButton)
	{
		[iTunesLocationField setStringValue:[panel filename]];
		[self changeITunesLocation:iTunesLocationField];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sharing Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)scheduleUpdateSharingInfo
{
	[updateSharingInfoTimer invalidate];
	[updateSharingInfoTimer release];
	
	updateSharingInfoTimer = [[NSTimer scheduledTimerWithTimeInterval:8.0
															   target:self
															 selector:@selector(updateSharingInfo:)
															 userInfo:data
															  repeats:NO] retain];
}

- (IBAction)sharingMatrixDidChange:(id)sender
{
	BOOL isFiltering = [sharingMatrix selectedRow] == 1;
	
	[sharingTable setEnabled:isFiltering];
	[self scheduleUpdateSharingInfo];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[item objectForKey:PLAYLIST_CHILDREN] count] > 0;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if(item == nil)
		return [[data playlistHeirarchy] count];
	else
		return [[item objectForKey:PLAYLIST_CHILDREN] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if(item == nil)
	{
		return [[data playlistHeirarchy] objectAtIndex:index];
	}
	else
	{
		NSArray *children = [item objectForKey:PLAYLIST_CHILDREN];
		NSString *childPersistentID = [children objectAtIndex:index];
		
		return [data playlistForPersistentID:childPersistentID];
	}
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return [item objectForKey:PLAYLIST_NAME];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
                                                  forTableColumn:(NSTableColumn *)tableColumn
                                                            item:(id)item
{
	[cell setState:[[item objectForKey:PLAYLIST_STATE] intValue]];
	
	int type = [[item objectForKey:PLAYLIST_TYPE] intValue];
	
	if(type == PLAYLIST_TYPE_MASTER)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesLibrary"]];
	}
	else if(type == PLAYLIST_TYPE_MUSIC)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesMusic"]];
	}
	else if(type == PLAYLIST_TYPE_MOVIES)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesMovies"]];
	}
	else if(type == PLAYLIST_TYPE_TVSHOWS)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesTVShows"]];
	}
	else if(type == PLAYLIST_TYPE_PODCASTS)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesPodcasts"]];
	}
	else if(type == PLAYLIST_TYPE_AUDIOBOOKS)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesAudiobooks"]];
	}
	else if(type == PLAYLIST_TYPE_VIDEOS)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesVideos"]];
	}
	else if(type == PLAYLIST_TYPE_PARTYSHUFFLE)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesPartyShuffle"]];
	}
	else if(type == PLAYLIST_TYPE_PURCHASED)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesPurchasedMusic"]];
	}
	else if(type == PLAYLIST_TYPE_FOLDER)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesFolder"]];
	}
	else if(type == PLAYLIST_TYPE_SMART)
	{
		[cell setImage:[NSImage imageNamed:@"iTunesSmartPlaylist"]];
	}
	else
	{
		[cell setImage:[NSImage imageNamed:@"iTunesPlaylist"]];
	}
}

- (void)outlineView:(NSOutlineView *)anOutlineView
	 didClickButton:(int)buttonIndex
	  atTableColumn:(NSTableColumn *)aTableColumn
				row:(int)rowIndex
{
	NSInteger selectedRow = [sharingTable selectedRow];
	if(selectedRow >= 0)
	{
		NSMutableDictionary *playlist = [sharingTable itemAtRow:selectedRow];
		
		[data toggleStateOfPlaylist:playlist];
		[sharingTable reloadData];
		
		[self scheduleUpdateSharingInfo];
	}
}

- (void)updateSharingInfo:(NSTimer *)aTimer
{
	id <HelperProtocol> helperProxy = [[NSApp delegate] helperProxy];
	
	BOOL isFiltering = [sharingMatrix selectedRow] == 1;
	[helperProxy setIsSharingFilterEnabled:isFiltering];
	
	// We extract the data from the timer, because if the user closed the window, the data variable will be nil
	ITunesLocalSharedData *sharedData = [aTimer userInfo];
	
	// Calling saveChanges on the sharedData automatically sends the changes to the helper
	[sharedData saveChanges];
	
	// Now we need to tell the helper to immediately update it's info
	[helperProxy forceUpdateITunesInfo];
	
	[updateSharingInfoTimer invalidate];
	[updateSharingInfoTimer autorelease];
	updateSharingInfoTimer = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Advanced Options
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)changeServerPort:(id)sender
{
	[[[NSApp delegate] helperProxy] setDefaultServerPortNumber:[sender intValue]];
}

- (IBAction)toggleDemoMode:(id)sender
{
	// This is most likely temporary code, so I'm just going to copy and paste
	[[NSNotificationCenter defaultCenter] postNotificationName:DidUpdateLocalServiceNotification object:self];
}

- (IBAction)toggleStuntFeedback:(id)sender
{
	BOOL flag = [sender state] == NSOnState;
	
	[[[NSApp delegate] helperProxy] sendStuntFeedback:flag];
}

- (IBAction)learnMoreAboutStuntFeedback:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_STUNT_INFO]];
}

@end
