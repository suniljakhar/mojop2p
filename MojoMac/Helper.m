#import "Helper.h"
#import "HelperAppDelegate.h"
#import "MojoDefinitions.h"
#import "MenuController.h"
#import "Subscriptions.h"
#import "LibrarySubscriptions.h"
#import "MojoHTTPServer.h"
#import "BonjourClient.h"
#import "BonjourResource.h"
#import "MojoXMPPClient.h"
#import "GatewayHTTPServer.h"
#import "RHKeychain.h"

@interface Helper (PrivateAPI)
- (BOOL)isLoginItem;
- (void)addLoginItem;
- (void)deleteLoginItem;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation Helper

- (id)init
{
	if((self = [super init]))
	{
		gateways = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[gateways release];
	[super dealloc];
}

- (void)awakeFromNib
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mojoConnectionDidDie:)
												 name:MojoConnectionDidDieNotification
											   object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the share name that is stored in the user defaults.
 * This may be an empty string, in which case no share name is set and the computer name is to be used.
**/
- (NSString *)shareName
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_SHARE_NAME];
}

/**
 * Returns the share name that is currently in effect.
 * If the share name in the user defaults system is an empty string,
 * then the computer name that is in effect is returned.
**/
- (NSString *)appliedShareName
{
	NSString *shareName = [self shareName];
	if((shareName == nil) || ([shareName length] == 0))
	{
		shareName = [(NSString *)SCDynamicStoreCopyComputerName(NULL, NULL) autorelease];
	}
	return shareName;
}

- (void)setShareName:(NSString *)newShareName
{
	// Watch out for nil strings, just to be safe, since this will cause crashes
	NSString *shareName = (newShareName == nil) ? @"" : newShareName;
	
	// Save the new share name into the user defaults system
	[[NSUserDefaults standardUserDefaults] setObject:shareName forKey:PREFS_SHARE_NAME];
		
	// Tell the mojo server to update it's share name
	// This will propogate the changes on the local network
	[[MojoHTTPServer sharedInstance] updateShareName];
	
	// Tell the XMPP client to update it's share name
	// This will propogate the changes on the internet
	[[MojoXMPPClient sharedInstance] updateShareName];
}

- (BOOL)requiresPassword
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD];
}

- (void)setRequiresPassword:(BOOL)flag
{
	// Save the new setting to the user defaults system
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_REQUIRE_PASSWORD];
	
	// Tell the mojo server to update it's setting
	// This will propogate the change on the local network
	[[MojoHTTPServer sharedInstance] updateRequiresPassword];
	
	// Tell the XMPP client to update it's setting
	// This will propogate the change on the internet
	[[MojoXMPPClient sharedInstance] updateRequiresPassword];
}

- (oneway void)passwordDidChange
{
	// Tell the mojo server to update it's setting
	// This will propogate the change on the local network
	[[MojoHTTPServer sharedInstance] updateRequiresPassword];
	
	// Tell the XMPP client to update it's setting
	// This will propogate the change on the internet
	[[MojoXMPPClient sharedInstance] updateRequiresPassword];
}

- (BOOL)requiresTLS
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_TLS];
}

- (oneway void)setRequiresTLS:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_REQUIRE_TLS];
	
	// Tell the mojo server to update it's setting
	// This will propogate the change on the local network
	[[MojoHTTPServer sharedInstance] updateRequiresTLS];
	
	// Tell the XMPP client to update it's setting
	// This will propogate the change on the internet
	[[MojoXMPPClient sharedInstance] updateRequiresTLS];
}

- (BOOL)isBackgroundHelperEnabled
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_BACKGROUND_HELPER_ENABLED];
}

- (void)setIsBackgroundHelperEnabled:(BOOL)flag
{
	// Save the new option into the user defaults system
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_BACKGROUND_HELPER_ENABLED];
	
	// This could potentially affect whether or not we should be displaying the menu item
	if(flag && [self shouldDisplayMenuItem]) {
		[menuController displayMenuItem];
	}
	else {
		[menuController hideMenuItem];
	}
}

- (BOOL)shouldLaunchAtLogin
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_LAUNCH_AT_LOGIN];
}

- (oneway void)setShouldLaunchAtLogin:(BOOL)flag
{
	// Save the new option into the user defaults system
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_LAUNCH_AT_LOGIN];
	
	// We need to either add or remove a login item at this point
	if([self isBackgroundHelperEnabled] && flag) {
		[self addLoginItem];
	}
	else {
		[self deleteLoginItem];
	}
}

- (BOOL)shouldDisplayMenuItem
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_DISPLAY_MENU_ITEM];
}

- (void)setShouldDisplayMenuItem:(BOOL)flag;
{
	// Save the new option into the user defaults system
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_DISPLAY_MENU_ITEM];
	
	// This could potentially affect whether or not we should be displaying the menu item
	if([self isBackgroundHelperEnabled] && flag) {
		[menuController displayMenuItem];
	}
	else {
		[menuController hideMenuItem];
	}
}

- (int)updateIntervalInMinutes
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_UPDATE_INTERVAL];
}

- (oneway void)setUpdateIntervalInMinutes:(int)minutes
{
	// Update the actual value in the user defaults system
	[[NSUserDefaults standardUserDefaults] setInteger:minutes forKey:PREFS_UPDATE_INTERVAL];
	
	// We don't want to immediately make these changes take effect...
	// Since the user may change his mind, and edit the value again in a few seconds
	// So we'll create a timer to fire in a moment, that will make the changes live when it fires
	[NSTimer scheduledTimerWithTimeInterval:30
									 target:[Subscriptions class]
								   selector:@selector(updateTimer:)
								   userInfo:nil
									repeats:NO];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isXMPPAutoLoginEnabled
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_AUTOLOGIN];
}

- (void)setIsXMPPAutoLoginEnabled:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_XMPP_AUTOLOGIN];
}

- (NSString *)XMPPUsername
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_USERNAME];
}

- (void)setXMPPUsername:(NSString *)username
{
	[[NSUserDefaults standardUserDefaults] setObject:username forKey:PREFS_XMPP_USERNAME];
}

- (NSString *)XMPPServer
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_SERVER];
}

- (void)setXMPPServer:(NSString *)server
{
	[[NSUserDefaults standardUserDefaults] setObject:server forKey:PREFS_XMPP_SERVER];
}

- (int)XMPPPort
{
	int port = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_XMPP_PORT];
	if(port < 1024 || port > 65535) port = 5222;
	
	return port;
}

- (void)setXMPPPort:(int)aPort
{
	int port = (aPort < 1 || aPort > 65535) ? 5222 : aPort;
	
	[[NSUserDefaults standardUserDefaults] setInteger:port forKey:PREFS_XMPP_PORT];
}

- (BOOL)XMPPServerUsesSSL
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_USESSL];
}

- (void)setXMPPServerUsesSSL:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_XMPP_USESSL];
}

- (BOOL)allowSelfSignedCertificate
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_ALLOWSELFSIGNED];
}

- (void)setAllowsSelfSignedCertificate:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_XMPP_ALLOWSELFSIGNED];
}

- (BOOL)allowSSLHostNameMismatch
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_ALLOWSSLMISMATCH];
}

- (oneway void)setAllowsSSLHostNameMismatch:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_XMPP_ALLOWSSLMISMATCH];
}

- (NSString *)XMPPResource
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_RESOURCE];
}

- (void)setXMPPResource:(NSString *)resource
{
	[[NSUserDefaults standardUserDefaults] setObject:resource forKey:PREFS_XMPP_RESOURCE];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int)playlistOption
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_PLAYLIST_OPTION];
}

- (void)setPlaylistOption:(int)playlistOption
{
	[[NSUserDefaults standardUserDefaults] setInteger:playlistOption forKey:PREFS_PLAYLIST_OPTION];
}

- (NSString *)playlistName
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_PLAYLIST_NAME];
}

- (void)setPlaylistName:(NSString *)newPlaylistName
{
	NSString *playlistName = (newPlaylistName != nil) ? newPlaylistName : @"Mojo";
	[[NSUserDefaults standardUserDefaults] setObject:playlistName forKey:PREFS_PLAYLIST_NAME];
}

- (NSString *)iTunesLocation
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_ITUNES_LOCATION];
}

- (void)setITunesLocation:(NSString *)xmlPath
{
	[[NSUserDefaults standardUserDefaults] setObject:xmlPath forKey:PREFS_ITUNES_LOCATION];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sharing Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isSharingFilterEnabled
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_SHARE_FILTER];
}

- (void)setIsSharingFilterEnabled:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_SHARE_FILTER];
}

- (NSArray *)sharedPlaylists
{
	return [[NSUserDefaults standardUserDefaults] arrayForKey:PREFS_SHARED_PLAYLISTS];
}

- (void)setSharedPlaylists:(NSArray *)sharedPlaylists
{
	[[NSUserDefaults standardUserDefaults] setObject:sharedPlaylists forKey:PREFS_SHARED_PLAYLISTS];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Advanced Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int)currentServerPortNumber
{
	return [[MojoHTTPServer sharedInstance] port];
}

- (int)defaultServerPortNumber
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_SERVER_PORT_NUMBER];
}

- (void)setDefaultServerPortNumber:(int)serverPortNumber
{
	// Validate given port number
	if((serverPortNumber != 0) && (serverPortNumber < 1024 && serverPortNumber > 65535))
	{
		// The port number is out of range - reset to zero
		serverPortNumber = 0;
	}
	
	// Save port number in the user defaults system
	[[NSUserDefaults standardUserDefaults] setInteger:serverPortNumber forKey:PREFS_SERVER_PORT_NUMBER];
	
	// Restart the server on the new port if necessary
	if((serverPortNumber != 0) && (serverPortNumber != [[MojoHTTPServer sharedInstance] port]))
	{
		[[MojoHTTPServer sharedInstance] stop];
		[[MojoHTTPServer sharedInstance] setPort:serverPortNumber];
		[[MojoHTTPServer sharedInstance] start:nil];
	}
}

- (BOOL)sendStuntFeedback
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_STUNT_FEEDBACK];
}

- (oneway void)sendStuntFeedback:(BOOL)flag
{
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:PREFS_STUNT_FEEDBACK];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Basic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)localhostServiceName
{
	return [[BonjourClient sharedInstance] localhostServiceName];
}

- (bycopy NSString *)stuntUUID
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:STUNT_UUID];
}

- (void)forceUpdateITunesInfo
{
	[[NSApp delegate] forceUpdateITunesInfo];
}

- (void)quit
{
	[NSApp terminate:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Subscriptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableArray *)sortedSubscriptionsByName
{
	return [Subscriptions sortedSubscriptionsByName];
}

- (LibrarySubscriptions *)subscriptionsCloneForLibrary:(NSString *)libID
{
	return [Subscriptions subscriptionsCloneForLibrary:libID];
}

- (void)setSubscriptions:(LibrarySubscriptions *)subscriptions forLibrary:(NSString *)libID
{
	[Subscriptions setSubscriptions:subscriptions forLibrary:libID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AppleScript methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isLoginItem
{
	/*  Execute the following AppleScript command:
	
	tell application "System Events"
	  if "<Application Name>" is in (name of every login item) then
	    return yes
	  else
	    return no
	  end if
	end tell
	*/
	
	NSMutableString *command = [NSMutableString string];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"MojoHelper\" is in (name of every login item) then \n"];
	[command appendString:@"return yes \n"];
	[command appendString:@"else \n"];
	[command appendString:@"return no \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];
	
	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	NSAppleEventDescriptor *ae = [script executeAndReturnError:nil];
	
	[script autorelease];
	
	return [[ae stringValue] hasPrefix:@"yes"];
}

- (void)addLoginItem
{
	/* Execute the following AppleScript command:
	
	set app_path to path to me
	tell application "System Events"
	  if "<Application Name>" is not in (name of every login item) then
	    make login item at end with properties {hidden:false, path:app_path}
	  end if
	end tell
	*/
	
	NSMutableString *command = [NSMutableString string];
	[command appendString:@"set app_path to path to me \n"];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"MojoHelper\" is not in (name of every login item) then \n"];
	[command appendString:@"make login item at end with properties {hidden:false, path:app_path} \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];
	
	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	[script executeAndReturnError:nil];
	[script release];
}

- (void)deleteLoginItem
{
	/* Execute the following AppleScript command:
	
	tell application "System Events"
	  if "<Application Name>" is in (name of every login item) then
	    delete (every login item whose name is "<Application Name>")
	  end if
	end tell
	*/
	
	NSMutableString *command = [NSMutableString string];
	[command appendString:@"tell application \"System Events\" \n"];
	[command appendString:@"if \"MojoHelper\" is in (name of every login item) then \n"];
	[command appendString:@"delete (every login item whose name is \"MojoHelper\") \n"];
	[command appendString:@"end if \n"];
	[command appendString:@"end tell"];
	
	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:command];
	[script executeAndReturnError:nil];
	[script release];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark BonjourClient Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Manually starts or stops the BonjourClient.
**/
- (void)bonjourClient_start
{
	[[BonjourClient sharedInstance] start];
}
- (void)bonjourClient_stop
{
	[[BonjourClient sharedInstance] stop];
}

/**
 * Returns the service name for our own local bonjour service.
**/
- (NSString *)bonjourClient_localhostServiceName
{
	return [[BonjourClient sharedInstance] localhostServiceName];
}

/**
 * Returns whether or not a bonjour user is known to be associated with the given libraryID.
**/
- (BOOL)bonjourClient_isLibraryAvailable:(NSString *)libID
{
	return [[BonjourClient sharedInstance] isLibraryAvailable:libID];
}

/**
 * Returns the bonjour user that has the given attribute.
 * If no user has the given attribute, then nil is returned.
**/
- (BonjourResource *)bonjourClient_resourceForLibraryID:(NSString *)libID
{
	return [[BonjourClient sharedInstance] resourceForLibraryID:libID];
}

/**
 * Changes the nickname for the bonjour resource with the given library ID.
**/
- (void)bonjourClient_setNickname:(NSString *)nickname forLibraryID:(NSString *)libID
{
	[[BonjourClient sharedInstance] setNickname:nickname forLibraryID:libID];
}

/**
 * Returns the local bonjour resources in an array.
**/
- (NSArray *)bonjourClient_unsortedResourcesIncludingLocalhost:(BOOL)flag
{
	return [[BonjourClient sharedInstance] unsortedResourcesIncludingLocalhost:flag];
}
- (NSArray *)bonjourClient_sortedResourcesByNameIncludingLocalhost:(BOOL)flag
{
	return [[BonjourClient sharedInstance] sortedResourcesByNameIncludingLocalhost:flag];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark MojoXMPPClient Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)xmpp_isMissingAccountInformation
{
	NSString *server = [self XMPPServer];
	if([server length] == 0)
	{
		return YES;
	}
	
	NSString *username = [self XMPPUsername];
	if([username length] == 0)
	{
		return YES;
	}
	
	NSString *password = [RHKeychain passwordForXMPPServer];
	if([password length] == 0)
	{
		return YES;
	}
	
	return NO;
}

/**
 * Manually starts the MojoXMPPClient.
**/
- (void)xmpp_start
{
	[[MojoXMPPClient sharedInstance] start];
}

/**
 * Manually stops the MojoXMPPClient.
**/
- (void)xmpp_stop
{
	[[MojoXMPPClient sharedInstance] stop];
}

/**
 * Returns whether or not a xmpp user is known to be associated with the given libraryID.
**/
- (BOOL)xmpp_isLibraryAvailable:(in bycopy NSString *)libID
{
	return [[MojoXMPPClient sharedInstance] isLibraryAvailable:libID];
}

/**
 * These methods return the xmpp user that has the given attribute.
 * If no user has the given attribute, then nil is returned.
**/
- (XMPPUser *)xmpp_userForRosterOrder:(int)rosterOrder
{
	return [[MojoXMPPClient sharedInstance] userForRosterOrder:rosterOrder];
}

- (NSUInteger)xmpp_rosterOrderForUser:(in bycopy XMPPUser *)user
{
	return [[MojoXMPPClient sharedInstance] rosterOrderForUser:user];
}

- (XMPPUserAndMojoResource *)xmpp_userAndMojoResourceForLibraryID:(NSString *)libID
{
	return [[MojoXMPPClient sharedInstance] userAndMojoResourceForLibraryID:libID];
}

/**
 * Returns the current connection state of the XMPPClient.
 * The state will be one of 3 things:
 * NSOffState, NSOnState, or NSMixedState
**/
- (int)xmpp_connectionState
{
	return [[MojoXMPPClient sharedInstance] connectionState];
}

/**
 * These methods provide for roster modification.
**/
- (void)xmpp_addBuddy:(XMPPJID *)jid withNickname:(NSString *)optionalName
{
	[[MojoXMPPClient sharedInstance] addBuddy:jid withNickname:optionalName];
}
- (void)xmpp_removeBuddy:(XMPPJID *)jid
{
	[[MojoXMPPClient sharedInstance] removeBuddy:jid];
}
- (void)xmpp_setNickname:(NSString *)nickname forBuddy:(XMPPJID *)jid
{
	[[MojoXMPPClient sharedInstance] setNickname:nickname forBuddy:jid];
}

/**
 * These methods offer access to the roster.
**/
- (NSArray *)xmpp_unsortedUserAndMojoResources
{
	return [[MojoXMPPClient sharedInstance] unsortedUserAndMojoResources];
}
- (NSArray *)xmpp_sortedUserAndMojoResources
{
	return [[MojoXMPPClient sharedInstance] sortedUserAndMojoResources];
}
- (NSArray *)xmpp_sortedUnavailableUsersByName
{
	return [[MojoXMPPClient sharedInstance] sortedUnavailableUsersByName];
}

- (XMPPJID *)xmpp_myJID
{
	return [[MojoXMPPClient sharedInstance] myJID];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Gateway Server
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method will create and start a gateway server for the given host and port.
 * Remote connections will automatically be created and attached to incoming local connections.
 * The gateway server will then forward data back and forth between the local and remote connection.
 *
 * The returned integer corresponds to the localhost socket that may be used to connect to the gateway.
 **/
- (UInt16)gateway_openServerForHost:(in bycopy NSString *)host port:(in bycopy UInt16)port
{
	GatewayHTTPServer *gateway = [[GatewayHTTPServer alloc] initWithHost:host port:port];
	
	UInt16 result = [gateway localPort];
	
	// Store opened gateway in dictionary, using localPort as key
	[gateways setObject:gateway forKey:[NSNumber numberWithUnsignedShort:result]];
	
	[gateway release];
	return result;
}

/**
 * This method will create and start a gateway server for the given JID.
 * Remote connections will automatically be created and attached to incoming local connections.
 * The gateway server will then forward data back and forth between the JID and the incoming connection.
 *
 * The returned integer corresponds to the socket on localhost that may be used to connect to the gateway.
 **/
- (UInt16)gateway_openServerForJID:(in bycopy XMPPJID *)jid
{
	GatewayHTTPServer *gateway = [[GatewayHTTPServer alloc] initWithJID:jid];
	
	UInt16 result = [gateway localPort];
	
	// Store opened gateway in dictionary, using localPort as key
	[gateways setObject:gateway forKey:[NSNumber numberWithUnsignedShort:result]];
	
	[gateway release];
	return result;
}

/**
 * This method should be called when an opened gateway server is no longer needed.
**/
- (oneway void)gateway_closeServerWithLocalPort:(UInt16)port
{
	[gateways removeObjectForKey:[NSNumber numberWithUnsignedShort:port]];
}

/**
 * Use this method to optionally secure an opened gateway server.
 * If set, remote connections to the configured host/port or JID will be sucured using SSL/TLS.
 * 
 * Localhost connections to the gateway server are not secured as they are not going over any network.
 **/
- (oneway void)gatewayWithLocalPort:(UInt16)port setIsSecure:(BOOL)useSSL
{
	GatewayHTTPServer *gateway = (GatewayHTTPServer *)[gateways objectForKey:[NSNumber numberWithUnsignedShort:port]];
	[gateway setIsSecure:useSSL];
}

/**
 * Use this method to optionally allow the gateway connections to automatically authenticate for requests.
 * This may be needed when streaming in QuickTime in Leopard, as the password mechanism is broke in 10.5.
 *
 * When this is set, 401 unauthorized responses from the remote host automatically receive a new authorized request.
 **/
- (oneway void)gatewayWithLocalPort:(UInt16)port
						setUsername:(bycopy NSString *)username
						   password:(bycopy NSString *)password
{
	GatewayHTTPServer *gateway = (GatewayHTTPServer *)[gateways objectForKey:[NSNumber numberWithUnsignedShort:port]];
	[gateway setUsername:username password:password];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Gateway Server
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)mojoConnectionDidDie:(NSNotification *)notification
{
	NSLog(@"Helper: mojoConnectionDidDie:");
	
	// If the connection dies, we can close all the gateway servers we opened for it
	[gateways removeAllObjects];
}

@end
