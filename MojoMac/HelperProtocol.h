#import <Foundation/Foundation.h>
#import "TigerSupport.h"

@class LibrarySubscriptions;
@class BonjourResource;
@class XMPPJID;
@class XMPPUser;
@class XMPPUserAndMojoResource;


@protocol HelperProtocol

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (bycopy NSString *)shareName;
- (bycopy NSString *)appliedShareName;
- (oneway void)setShareName:(in bycopy NSString *)shareName;

- (BOOL)requiresPassword;
- (oneway void)setRequiresPassword:(BOOL)flag;
- (oneway void)passwordDidChange;

- (BOOL)requiresTLS;
- (oneway void)setRequiresTLS:(BOOL)flag;

- (BOOL)isBackgroundHelperEnabled;
- (oneway void)setIsBackgroundHelperEnabled:(BOOL)flag;

- (BOOL)shouldLaunchAtLogin;
- (oneway void)setShouldLaunchAtLogin:(BOOL)flag;

- (BOOL)shouldDisplayMenuItem;
- (oneway void)setShouldDisplayMenuItem:(BOOL)flag;

- (int)updateIntervalInMinutes;
- (oneway void)setUpdateIntervalInMinutes:(int)minutes;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Account Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isXMPPAutoLoginEnabled;
- (oneway void)setIsXMPPAutoLoginEnabled:(BOOL)flag;

- (bycopy NSString *)XMPPUsername;
- (oneway void)setXMPPUsername:(in bycopy NSString *)username;

- (bycopy NSString *)XMPPServer;
- (oneway void)setXMPPServer:(in bycopy NSString *)server;

- (int)XMPPPort;
- (oneway void)setXMPPPort:(int)port;

- (BOOL)XMPPServerUsesSSL;
- (oneway void)setXMPPServerUsesSSL:(BOOL)flag;

- (BOOL)allowSelfSignedCertificate;
- (oneway void)setAllowsSelfSignedCertificate:(BOOL)flag;

- (BOOL)allowSSLHostNameMismatch;
- (oneway void)setAllowsSSLHostNameMismatch:(BOOL)flag;

- (bycopy NSString *)XMPPResource;
- (oneway void)setXMPPResource:(in bycopy NSString *)resource;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int)playlistOption;
- (oneway void)setPlaylistOption:(int)playlistOption;

- (bycopy NSString *)playlistName;
- (oneway void)setPlaylistName:(in bycopy NSString *)playlistName;

- (bycopy NSString *)iTunesLocation;
- (oneway void)setITunesLocation:(in bycopy NSString *)xmlPath;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sharing Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isSharingFilterEnabled;
- (oneway void)setIsSharingFilterEnabled:(BOOL)flag;

- (bycopy NSArray *)sharedPlaylists;
- (oneway void)setSharedPlaylists:(in bycopy NSArray *)sharedPlaylists;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Advanced Preferences
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (int)currentServerPortNumber;
- (int)defaultServerPortNumber;
- (oneway void)setDefaultServerPortNumber:(int)serverPortNumber;

- (BOOL)sendStuntFeedback;
- (oneway void)sendStuntFeedback:(BOOL)flag;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Basic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (bycopy NSString *)localhostServiceName;
- (bycopy NSString *)stuntUUID;
- (oneway void)forceUpdateITunesInfo;
- (oneway void)quit;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Subscriptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a mutable array of LibrarySubscription objects.
**/
- (bycopy NSMutableArray *)sortedSubscriptionsByName;

- (bycopy LibrarySubscriptions *)subscriptionsCloneForLibrary:(bycopy in NSString *)libID;
- (oneway void)setSubscriptions:(bycopy in LibrarySubscriptions *)subscriptions forLibrary:(bycopy in NSString *)libID;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark BonjourClient Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Manually starts or stops the BonjourClient.
**/
- (oneway void)bonjourClient_start;
- (oneway void)bonjourClient_stop;

/**
 * Returns the service name for our own local bonjour service.
**/
- (bycopy NSString *)bonjourClient_localhostServiceName;

/**
 * Returns whether or not a bonjour user is known to be associated with the given libraryID.
**/
- (BOOL)bonjourClient_isLibraryAvailable:(in bycopy NSString *)libID;

/**
 * Returns the bonjour user that has the given attribute.
 * If no user has the given attribute, then nil is returned.
**/
- (bycopy BonjourResource *)bonjourClient_resourceForLibraryID:(in bycopy NSString *)libID;

/**
 * Changes the nickname for the bonjour resource with the given library ID.
**/
- (oneway void)bonjourClient_setNickname:(in bycopy NSString *)nickname forLibraryID:(in bycopy NSString *)libID;

/**
 * Returns the local bonjour users in an array.
**/
- (bycopy NSArray *)bonjourClient_unsortedResourcesIncludingLocalhost:(BOOL)flag;
- (bycopy NSArray *)bonjourClient_sortedResourcesByNameIncludingLocalhost:(BOOL)flag;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPP Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns YES if the user is missing account information.
**/
- (BOOL)xmpp_isMissingAccountInformation;

/**
 * Manually starts or stops the MojoXMPPClient.
**/
- (oneway void)xmpp_start;
- (oneway void)xmpp_stop;

/**
 * Returns the current connection state of the XMPPClient.
 * The state will be one of 3 things:
 * NSOffState, NSOnState, or NSMixedState
**/
- (int)xmpp_connectionState;

/**
 * Returns the user with the given roster order index.
 * If no user has a roster order with the given index, then nil is returned.
**/
- (bycopy XMPPUser *)xmpp_userForRosterOrder:(int)index;

/**
 * Returns the roster order for the given user.
 * If the given user is not in the roster, returns NSNotFound.
**/
- (NSUInteger)xmpp_rosterOrderForUser:(in bycopy XMPPUser *)user;

/**
 * Returns whether or not a xmpp user is known to be associated with the given libraryID.
**/
- (BOOL)xmpp_isLibraryAvailable:(in bycopy NSString *)libID;

/**
 * Returns the resource with the given library ID.
 * If there are no available resources with the given library ID, then nil is returned.
**/
- (bycopy XMPPUserAndMojoResource *)xmpp_userAndMojoResourceForLibraryID:(in bycopy NSString *)libID;

/**
 * These methods provide for roster modification.
**/
- (oneway void)xmpp_addBuddy:(in bycopy XMPPJID *)jid withNickname:(in bycopy NSString *)optionalName;
- (oneway void)xmpp_removeBuddy:(in bycopy XMPPJID *)jid;
- (oneway void)xmpp_setNickname:(in bycopy NSString *)nickname forBuddy:(in bycopy XMPPJID *)jid;

/**
 * Returns an array of XMPPUserAndMojoResource objects.
 * This includes all available mojo resources, including every resource for every online user,
 * and every resource for our own user (excluding our own resource).
**/
- (bycopy NSArray *)xmpp_unsortedUserAndMojoResources;
- (bycopy NSArray *)xmpp_sortedUserAndMojoResources;

/**
 * Returns all xmpp users that don't have any available mojo resources.
**/
- (bycopy NSArray *)xmpp_sortedUnavailableUsersByName;

/**
 * Returns our own JID, complete with resource, if available.
**/
- (bycopy XMPPJID *)xmpp_myJID;

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
- (UInt16)gateway_openServerForHost:(in bycopy NSString *)host port:(in bycopy UInt16)port;

/**
 * This method will create and start a gateway server for the given JID.
 * Remote connections will automatically be created and attached to incoming local connections.
 * The gateway server will then forward data back and forth between the JID and the incoming connection.
 *
 * The returned integer corresponds to the socket on localhost that may be used to connect to the gateway.
**/
- (UInt16)gateway_openServerForJID:(in bycopy XMPPJID *)jid;

/**
 * This method should be called when an opened gateway server is no longer needed.
**/
- (oneway void)gateway_closeServerWithLocalPort:(UInt16)port;

/**
 * Use this method to optionally secure an opened gateway server.
 * If set, remote connections to the configured host/port or JID will be sucured using SSL/TLS.
 * 
 * Localhost connections to the gateway server are not secured as they are not going over any network.
**/
- (oneway void)gatewayWithLocalPort:(UInt16)port setIsSecure:(BOOL)useSSL;

/**
 * Use this method to optionally allow the gateway connections to automatically authenticate for requests.
 * This may be needed when streaming in QuickTime in Leopard, as the password mechanism is broke in 10.5.
 *
 * When this is set, 401 unauthorized responses from the remote host automatically receive a new authorized request.
**/
- (oneway void)gatewayWithLocalPort:(UInt16)port
						setUsername:(bycopy NSString *)username
						   password:(bycopy NSString *)password;

@end