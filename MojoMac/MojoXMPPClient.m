#import <Cocoa/Cocoa.h>
#import "MojoXMPPClient.h"
#import "MojoDefinitions.h"
#import "RHKeychain.h"
#import "AsyncSocket.h"
#import "STUNTSocket.h"
#import "STUNSocket.h"
#import "TURNSocket.h"
#import "PseudoTcp.h"
#import "PseudoAsyncSocket.h"
#import "MojoHTTPServer.h"
#import "ITunesSearch.h"
#import "RHData.h"
#import "DDData.h"

#define TAG_AVAILABLE    12345
#define TAG_UNAVAILABLE  54321


@interface MojoXMPPClient (PrivateAPI)

- (BOOL)isTxtRecordReady;

- (void)onDidGoOnline;
- (void)onDidGoOffline;

- (BOOL)isDiscoQuery:(XMPPIQ *)iq;
- (void)replyToDiscoQuery:(XMPPIQ *)iq;
- (BOOL)isSearchQuery:(XMPPIQ *)iq;
- (void)handleSearchQuery:(XMPPIQ *)iq;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation MojoXMPPClient

static MojoXMPPClient *sharedInstance;

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
		sharedInstance = [[MojoXMPPClient alloc] init];
	}
}

/**
 * Returns the shared instance that all objects in this application can use.
**/
+ (MojoXMPPClient *)sharedInstance
{
	return sharedInstance;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard Constructor
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
		[self setPriority:0];
		
		txtRecord        = [[NSMutableDictionary alloc] initWithCapacity:7];
		
		turnConnections  = [[NSMutableArray alloc] initWithCapacity:4];
		stunConnections  = [[NSMutableArray alloc] initWithCapacity:4];
		stuntConnections = [[NSMutableArray alloc] initWithCapacity:4];
	}
	return self;
}

- (void)dealloc
{
	[txtRecord release];
	[turnConnections release];
	[stunConnections release];
	[stuntConnections release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)randomString
{
	NSString *pool = @"aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ0123456789";
	
	unsigned pos1 = arc4random() % [pool length];
	unsigned pos2 = arc4random() % [pool length];
	unsigned pos3 = arc4random() % [pool length];
	unsigned pos4 = arc4random() % [pool length];
	
	unichar char1 = [pool characterAtIndex:pos1];
	unichar char2 = [pool characterAtIndex:pos2];
	unichar char3 = [pool characterAtIndex:pos3];
	unichar char4 = [pool characterAtIndex:pos4];
	
	return [NSString stringWithFormat:@"%C%C%C%C", char1, char2, char3, char4];
}

- (void)start
{
	if([self isDisconnected])
	{
		NSString *jidStr = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_USERNAME];
		
		NSString *resource = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_RESOURCE];
		if((resource == nil) || ([resource length] == 0))
		{
			CFStringRef computerName = (CFStringRef)SCDynamicStoreCopyComputerName(NULL, NULL);
			
			resource = [NSString stringWithFormat:@"%@-%@", computerName, [self randomString]];
			
			if(computerName) CFRelease(computerName);
		}
		
		XMPPJID *jid = [XMPPJID jidWithString:jidStr resource:resource];
		
		if(jid == nil) return;
		
		NSString *myPassword = [RHKeychain passwordForXMPPServer];
		
		if(myPassword == nil) return;
				
		NSString *myDomain = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_XMPP_SERVER];
		int myPort = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_XMPP_PORT];
		
		BOOL allowSSC = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_ALLOWSELFSIGNED];
		BOOL allowSSLHNMM = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_ALLOWSSLMISMATCH];
		
		BOOL useSSL = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_XMPP_USESSL];
		
		[self setMyJID:jid];
		[self setPassword:myPassword];
		[self setDomain:myDomain];
		[self setPort:myPort];
		[self setAllowsSelfSignedCertificates:allowSSC];
		[self setAllowsSSLHostNameMismatch:allowSSLHNMM];
		[self setUsesOldStyleSSL:useSSL];
		[self connect];
	}
}

- (void)stop
{
	[self disconnect];
}

/**
 * Returns the general connection state. This method will return NSOffState if disconnected,
 * NSOnState if the connection is active, and ready to send and receive presence and messages, or NSMixedState if
 * the connection is being established, the stream is being negotiated, or the user is still being authenticated.
**/
- (int)connectionState
{
	if([self isDisconnected])
	{
		return NSOffState;
	}
	else if([self isConnected])
	{
		if([self isAuthenticated])
			return NSOnState;
		else
			return NSMixedState;
	}
	else
		return NSMixedState;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Presence Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides XMPPClient's goOnline method.
 * Takes care of adding the txt record to the presence message.
 * Also uses XMPPStream's sendElement:andNotifyMe: method so we can invoke xmppClientDidGoOnline.
 *
 * Note: This method is automatically called by XMPPClient due to autoPresence.
**/
- (void)goOnline
{
	if([self isTxtRecordReady] && [self isConnected] && [self isAuthenticated])
	{
		NSXMLElement *txtRecordElement = [NSXMLElement elementWithName:@"x" xmlns:@"mojo:x:txtrecord"];
		
		NSArray *allKeys = [txtRecord allKeys];
		int i;
		
		for(i = 0; i < [allKeys count]; i++)
		{
			NSString *key   = (NSString *)[allKeys objectAtIndex:i];
			NSString *value = (NSString *)[txtRecord objectForKey:key];
			
			[txtRecordElement addChild:[NSXMLNode elementWithName:key stringValue:value]];
		}
		
		NSString *priorityStr = [NSString stringWithFormat:@"%i", priority];
		
		NSXMLElement *presence = [NSXMLElement elementWithName:@"presence"];
		[presence addChild:[NSXMLElement elementWithName:@"priority" stringValue:priorityStr]];
		[presence addChild:[NSXMLElement elementWithName:@"show" stringValue:@"xa"]];
		[presence addChild:[NSXMLElement elementWithName:@"status" stringValue:@"Mojo Client - No Messaging"]];
		[presence addChild:txtRecordElement];
		
		[xmppStream sendElement:presence andNotifyMe:TAG_AVAILABLE];
	}
}

/**
 * Overrides XMPPClient's goOffline method.
 * Uses XMPPStream's sendElement:andNotifyMe: method so we can invoke xmppClientDidGoOffline.
**/
- (void)goOffline
{
	if([self isConnected] && [self isAuthenticated])
	{
		NSXMLElement *presence = [NSXMLElement elementWithName:@"presence"];
		[presence addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:@"unavailable"]];
		
		[xmppStream sendElement:presence andNotifyMe:TAG_UNAVAILABLE];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Overriden Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Overrides XMPPClient: sortedUsersByName.
 * MojoXMPPClient redefines the display name of a user by including the mojo txt record.
**/
- (NSArray *)sortedUsersByName
{
	return [[roster allValues] sortedArrayUsingSelector:@selector(compareByMojoName:)];
}

/**
 * Overrides XMPPClient: sortedUsersByAvailabilityName.
 * MojoXMPPClient redefines an available user to be one with a mojo resource.
 * MojoXMPPClient redefines the display name of a user by including the mojo txt record.
**/
- (NSArray *)sortedUsersByAvailabilityName
{
	return [[roster allValues] sortedArrayUsingSelector:@selector(compareByMojoAvailabilityName:)];
}

/**
 * Overrides XMPPClient: sortedAvailableUsersByName.
 * MojoXMPPClient redefines an available user to be one with a mojo resource.
 * 
 * Returns an array of XMPPUsers, all of which have at least one associated mojo resource.
**/
- (NSArray *)sortedAvailableUsersByName
{
	return [[self unsortedAvailableUsers] sortedArrayUsingSelector:@selector(compareByMojoName:)];
}

/**
 * Overrides XMPPClient: sortedUnavailableUsersByName.
 * MojoXMPPClient redefines an available user to be one with a mojo resource.
 * 
 * Returns an array of XMPPusers, all of which have zero associated mojo resources.
**/
- (NSArray *)sortedUnavailableUsersByName
{
	return [[self unsortedUnavailableUsers] sortedArrayUsingSelector:@selector(compareByMojoName:)];
}

/**
 * No need to override this method.
**/
- (NSArray *)unsortedUsers
{
	return [super unsortedUsers];
}

/**
 * Overrides XMPPClient: unsortedAvailableUsers.
 * MojoXMPPClient redefines an available user to be one with a mojo resource.
 * 
 * Returns an array of XMPPUsers, all of which have at least one associated mojo resource.
**/
- (NSArray *)unsortedAvailableUsers
{
	NSArray *allUsers = [self unsortedUsers];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[allUsers count]];
	
	int i;
	for(i = 0; i < [allUsers count]; i++)
	{
		XMPPUser *user = [allUsers objectAtIndex:i];
		
		if([user hasMojoResource])
		{
			[result addObject:user];
		}
	}
	
	return result;
}

/**
 * Overrides XMPPClient: unsortedUnavailableUsers.
 * MojoXMPPClient redefines an available user to be one with a mojo resource.
 *
 * Returns an array of XMPPUsers, all of which have no associated mojo resources.
**/
- (NSArray *)unsortedUnavailableUsers
{
	NSArray *allUsers = [self unsortedUsers];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[allUsers count]];
	
	int i;
	for(i = 0; i < [allUsers count]; i++)
	{
		XMPPUser *user = [allUsers objectAtIndex:i];
		
		if(![user hasMojoResource])
		{
			[result addObject:user];
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns all resources, including every resource for every online user,
 * and every resource for our own user (excluding our own resource).
 * 
 * The result is an array of XMPPUserAndMojoResource objects.
**/
- (NSArray *)unsortedUserAndMojoResources
{
	NSUInteger i, j;
	
	// Add all the resouces from all the available users in the roster
	
	NSArray *availableUsers = [self unsortedAvailableUsers];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[availableUsers count]];
	
	for(i = 0; i < [availableUsers count]; i++)
	{
		XMPPUser *user = [availableUsers objectAtIndex:i];
		NSArray *resources = [user unsortedMojoResources];
		
		for(j = 0; j < [resources count]; j++)
		{
			XMPPResource *resource = [resources objectAtIndex:j];
			
			XMPPUserAndMojoResource *temp = [[XMPPUserAndMojoResource alloc] initWithUser:user resource:resource];
			
			[result addObject:temp];
			[temp release];
		}
	}
	
	// Now add all the available resources from our own user account (excluding ourselves)
	
	NSArray *myResources = [myUser unsortedMojoResources];
	
	for(i = 0; i < [myResources count]; i++)
	{
		XMPPResource *resource = [myResources objectAtIndex:i];
		
		if(![myJID isEqual:[resource jid]])
		{
			XMPPUserAndMojoResource *temp = [[XMPPUserAndMojoResource alloc] initWithUser:myUser resource:resource];
			
			[result addObject:temp];
			[temp release];
		}
	}
	
	return result;
}

/**
 * Returns all resources, including every resource for every online user,
 * and every resource for our own user (excluding our own resource).
 * 
 * The result is an array of XMPPUserAndMojoResource objects, sorted by mojoDisplayName.
**/
- (NSArray *)sortedUserAndMojoResources
{
	return [[self unsortedUserAndMojoResources] sortedArrayUsingSelector:@selector(compare:)];
}

- (BOOL)isLibraryAvailable:(NSString *)libID
{
	XMPPUserAndMojoResource *userAndResource = [self userAndMojoResourceForLibraryID:libID];
	return (userAndResource != nil);
}

/**
 * Returns the user and resource object for the resource with the given iTunes library ID.
 * This is done by looping through every available mojo resources,
 * and looking for one with an advertised library ID that equals the given libID.
**/
- (XMPPUserAndMojoResource *)userAndMojoResourceForLibraryID:(NSString *)libID
{
	NSArray *availableUsers = [self unsortedAvailableUsers];
	
	NSUInteger i;
	for(i = 0; i < [availableUsers count]; i++)
	{
		XMPPUser *user = [availableUsers objectAtIndex:i];
		XMPPResource *resource = [user resourceForLibraryID:libID];
		
		if(resource)
		{
			return [[[XMPPUserAndMojoResource alloc] initWithUser:user resource:resource] autorelease];
		}
	}
	return nil;
}

/**
 * Returns the user with given roster order index, or nil.
 * Roster order is the order in which the xmpp server returns the list of users.
 * This order is not persistent - it may change upon each connection to the server.
**/
- (XMPPUser *)userForRosterOrder:(NSInteger)index
{
	NSArray *allUsers = [self unsortedUsers];
	
	if(index >= [allUsers count]) return nil;
	
	// Sort the list according to roster order
	NSArray *sorted = [allUsers sortedArrayUsingSelector:@selector(strictRosterOrderCompare:)];
	
	// Ensure that at least 2 of the three is online.
	// This is done by moving 2 online users to the beginning of the array.
	NSMutableArray *pseudoSorted = [NSMutableArray arrayWithCapacity:[sorted count]];
	
	NSUInteger i, j;
	for(i = j = 0; i < [sorted count]; i++)
	{
		XMPPUser *user = [sorted objectAtIndex:i];
		
		if(j < 2 && [user hasMojoResource])
		{
			[pseudoSorted insertObject:user atIndex:j];
			j++;
		}
		else
		{
			[pseudoSorted addObject:user];
		}
	}
	
	return [pseudoSorted objectAtIndex:index];
}

- (NSUInteger)rosterOrderForUser:(XMPPUser *)user
{
	// Always allow users to connect to themselves
	if([user isEqual:[self myUser]])
	{
		return 0;
	}
	
	NSArray *allUsers = [self unsortedUsers];
	
	// Sort the list according to roster order
	NSArray *sorted = [allUsers sortedArrayUsingSelector:@selector(strictRosterOrderCompare:)];
	
	// Ensure that at least 2 of the three is online.
	// This is done by moving 2 online users to the beginning of the array.
	NSMutableArray *pseudoSorted = [NSMutableArray arrayWithCapacity:[sorted count]];
	
	NSUInteger i, j;
	for(i = j = 0; i < [sorted count]; i++)
	{
		XMPPUser *user = [sorted objectAtIndex:i];
		
		if(j < 2 && [user hasMojoResource])
		{
			[pseudoSorted insertObject:user atIndex:j];
			j++;
		}
		else
		{
			[pseudoSorted addObject:user];
		}
	}
	
	return [pseudoSorted indexOfObject:user];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setupTxtRecord
{
	if([txtRecord count] == 0)
	{
		NSString *reqPasswd = @"0";
		if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD])
		{
			NSString *serverPasswd = [RHKeychain passwordForHTTPServer];
			if((serverPasswd != nil) && ([serverPasswd length] > 0))
			{
				reqPasswd = @"1";
			}
		}
		
//		// Todo: Implement support for TLS
//		NSString *reqTLS = @"0";
//		if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_TLS])
//		{
//			reqTLS = @"1";
//		}
		
		NSString *shareName = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_SHARE_NAME];
		if((shareName == nil) || ([shareName length] == 0))
		{
			shareName = [(NSString *)SCDynamicStoreCopyComputerName(NULL, NULL) autorelease];
		}
		
		[txtRecord setObject:@"2"        forKey:TXTRCD_VERSION];
		[txtRecord setObject:@"1"        forKey:TXTRCD_ZLIB_SUPPORT];
		[txtRecord setObject:@"1"        forKey:TXTRCD_GZIP_SUPPORT];
		[txtRecord setObject:@"1.1"      forKey:TXTRCD_STUNT_VERSION];
		[txtRecord setObject:@"1.0"      forKey:TXTRCD_STUN_VERSION];
		[txtRecord setObject:@"1.0"      forKey:TXTRCD_SEARCH_VERSION];
		[txtRecord setObject:reqPasswd   forKey:TXTRCD_REQUIRES_PASSWORD];
		[txtRecord setObject:shareName   forKey:TXTRCD2_SHARE_NAME];
	}
}

- (void)setITunesLibraryID:(NSString *)libID numberOfSongs:(int)numSongs
{
	if([txtRecord count] == 0)
	{
		[self setupTxtRecord];
	}
	
	NSString *numSongsStr = [NSString stringWithFormat:@"%i", numSongs];
	
	[txtRecord setObject:libID       forKey:TXTRCD2_LIBRARY_ID];
	[txtRecord setObject:numSongsStr forKey:TXTRCD2_NUM_SONGS];
	
	[self goOnline];
}

- (void)updateShareName
{
	NSString *shareName = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_SHARE_NAME];
	
	// With Bonjour, we can simply use an empty share name, because bonjour itself broadcasts the computer name.
	// However, with XMPP we only have an ungly JID to back us up.
	// Prefer a friendlier computer name over a JID.
	// This also matches the GUI we present the user in the preferences window.
	
	if((shareName == nil) || ([shareName length] == 0))
	{
		shareName = [(id)SCDynamicStoreCopyComputerName(NULL, NULL) autorelease];
	}
	
	[txtRecord setObject:shareName forKey:TXTRCD2_SHARE_NAME];
	
	[self goOnline];
}

- (void)updateRequiresPassword
{
	BOOL requiresPassword = NO;
	if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD])
	{
		NSString *serverPassword = [RHKeychain passwordForHTTPServer];
		if((serverPassword != nil) && ([serverPassword length] > 0))
		{
			requiresPassword = YES;
		}
	}
	
	if(requiresPassword)
		[txtRecord setObject:@"1" forKey:TXTRCD_REQUIRES_PASSWORD];
	else
		[txtRecord setObject:@"0" forKey:TXTRCD_REQUIRES_PASSWORD];
	
	[self goOnline];
}

- (void)updateRequiresTLS
{
//	BOOL requiresTLS = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_TLS];
//	BOOL requiresTLS = NO;
//	
//	if(requiresTLS)
//		[txtRecord setObject:@"1" forKey:TXTRCD_REQUIRES_TLS];
//	else
//		[txtRecord setObject:@"0" forKey:TXTRCD_REQUIRES_TLS];
//	
//	[self goOnline];
}

- (BOOL)isTxtRecordReady
{
	if(![txtRecord objectForKey:TXTRCD2_LIBRARY_ID] || ![txtRecord objectForKey:TXTRCD2_NUM_SONGS])
		return NO;
	else
		return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delegate Helper Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Override's XMPPClient's method.
 * We do this because we want to immediately disconnect if authentication fails.
 * This allows the user to change account and/or server settings if needed.
**/
- (void)onDidNotAuthenticate:(NSXMLElement *)error
{
	[multicastDelegate xmppClient:self didNotAuthenticate:error];
	
	[self disconnect];
}

- (void)onDidGoOnline
{
	[multicastDelegate xmppClientDidGoOnline:self];
}

- (void)onDidGoOffline
{
	[multicastDelegate xmppClientDidGoOffline:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPStream Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
	if([STUNTSocket isNewStartStuntMessage:message])
	{
		// This is the first message for an incoming STUNT (TCP NAT Traversal) connection
		STUNTSocket *stuntSocket = [[STUNTSocket alloc] initWithStuntMessage:message];
		
		[stuntConnections addObject:stuntSocket];
		
		[stuntSocket start:self];
		[stuntSocket release];
	}
	else if([STUNSocket isNewStartStunMessage:message])
	{
		// This is the first message for an incoming STUN (UDP NAT Traversal) connection
		STUNSocket *stunSocket = [[STUNSocket alloc] initWithStunMessage:message];
		
		[stunConnections addObject:stunSocket];
		
		[stunSocket start:self];
		[stunSocket release];
	}
	else
	{
		[super xmppStream:sender didReceiveMessage:message];
	}
}

- (void)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
	if([self isDiscoQuery:iq])
	{
		[self replyToDiscoQuery:iq];
	}
	else if([self isSearchQuery:iq])
	{
		[self handleSearchQuery:iq];
	}
	else if([TURNSocket isNewStartTurnRequest:iq])
	{
		// This is the first message for an incoming TURN (Proxy) connection
		TURNSocket *turnSocket = [[TURNSocket alloc] initWithTurnRequest:iq];
		
		[turnConnections addObject:turnSocket];
		
		[turnSocket start:self];
		[turnSocket release];
	}
	else
	{
		[super xmppStream:sender didReceiveIQ:iq];
	}
}

- (void)xmppStream:(XMPPStream *)sender didSendElementWithTag:(long)tag
{
	if(tag == TAG_AVAILABLE)
	{
		[self onDidGoOnline];
	}
	else if(tag == TAG_UNAVAILABLE)
	{
		[self onDidGoOffline];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom IQ Responses
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isDiscoQuery:(XMPPIQ *)iq
{
	// An incoming disco query looks like this:
	// 
	// <iq type="get" from="[jid full]" id="uuid">
	//   <query xmlns="http://jabber.org/protocol/disco#info"/>
	// </iq>
	
	NSString *iqType = [[iq attributeForName:@"type"] stringValue];
	if(![iqType isEqualToString:@"get"])
	{
		return NO;
	}
	
	NSXMLElement *discoQuery = [iq elementForName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
	if(discoQuery == nil)
	{
		return NO;
	}
	
	return YES;
}

- (void)replyToDiscoQuery:(XMPPIQ *)iq
{
	NSXMLElement *identity = [NSXMLElement elementWithName:@"identity"];
	[identity addAttributeWithName:@"category" stringValue:@"proxy"];
	[identity addAttributeWithName:@"type" stringValue:@"bytestreams"];
	[identity addAttributeWithName:@"name" stringValue:@"SOCKS5 Bytestreams Service"];
	
	NSXMLElement *feature = [NSXMLElement elementWithName:@"feature"];
	[feature addAttributeWithName:@"var" stringValue:@"http://jabber.org/protocol/bytestreams"];
	
	NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
	[query addChild:identity];
	[query addChild:feature];
	
	NSXMLElement *iqResponse = [NSXMLElement elementWithName:@"iq"];
	[iqResponse addAttributeWithName:@"type" stringValue:@"result"];
	[iqResponse addAttributeWithName:@"to" stringValue:[[iq from] full]];
	if([iq elementID])
	{
		[iqResponse addAttributeWithName:@"id" stringValue:[iq elementID]];
	}
	[iqResponse addChild:query];
	
	[self sendElement:iqResponse];
}

- (BOOL)isSearchQuery:(XMPPIQ *)iq
{
	// An incoming search query looks like this:
	// 
	// <iq type="get" from="[jid full]" id="uuid">
	//   <query xmlns="deusty:iq:search">
	//     <search q="john mayer" num="50"/>
	//   </query>
	// </iq>
	
	NSString *iqType = [[iq attributeForName:@"type"] stringValue];
	if(![iqType isEqualToString:@"get"])
	{
		return NO;
	}
	
	NSXMLElement *searchQuery = [iq elementForName:@"query" xmlns:@"deusty:iq:search"];
	if(searchQuery == nil)
	{
		return NO;
	}
	
	return YES;
}

- (void)handleSearchQuery:(XMPPIQ *)iq
{
	[NSThread detachNewThreadSelector:@selector(search:) toTarget:self withObject:iq];
}

- (void)search:(XMPPIQ *)iqRequest
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSXMLElement *queryRequest = [iqRequest elementForName:@"query" xmlns:@"deusty:iq:search"];
	NSXMLElement *searchRequest = [queryRequest elementForName:@"search"];
	
	NSDictionary *query = [searchRequest attributesAsDictionary];
	
	ITunesSearch *search = [[[ITunesSearch alloc] initWithSearchQuery:query] autorelease];
	
	NSString *errorString = nil;
	NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:[search matchingTracks]
																   format:NSPropertyListXMLFormat_v1_0
														 errorDescription:&errorString];
	
	BOOL useZlib = NO;
	NSString *compression = [query objectForKey:@"compression"];
	if(compression)
	{
		NSRange range = [compression rangeOfString:@"zlib"];
		if(range.length > 0)
		{
			useZlib = YES;
		}
	}
	
	NSData *compressedData;
	if(useZlib)
		compressedData = [plistData zlibDeflateWithCompressionLevel:9];
	else
		compressedData = [plistData gzipDeflateWithCompressionLevel:9];
		
	NSString *base64Response = [compressedData base64Encoded];
	
	NSXMLElement *searchResponse = [NSXMLElement elementWithName:@"search"];
	[searchResponse setStringValue:base64Response];
	
	if(useZlib)
		[searchResponse addAttributeWithName:@"compression" stringValue:@"zlib"];
	else
		[searchResponse addAttributeWithName:@"compression" stringValue:@"gzip"];
	
	NSXMLElement *queryResponse = [NSXMLElement elementWithName:@"query" xmlns:@"deusty:iq:search"];
	[queryResponse addChild:searchResponse];
	
	NSXMLElement *iqResponse = [NSXMLElement elementWithName:@"iq"];
	[iqResponse addAttributeWithName:@"type" stringValue:@"result"];
	[iqResponse addAttributeWithName:@"to" stringValue:[[iqRequest from] full]];
	[iqResponse addAttributeWithName:@"id" stringValue:[iqRequest elementID]];
	[iqResponse addChild:queryResponse];
	
	[self performSelectorOnMainThread:@selector(searchDidFinish:)
						   withObject:iqResponse
						waitUntilDone:NO
								modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	[pool release];
}

- (void)searchDidFinish:(NSXMLElement *)searchResponse
{
	[self sendElement:searchResponse];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark STUNT Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)stuntSocket:(STUNTSocket *)sender didSucceed:(AsyncSocket *)connectedSocket
{
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// The incoming stunt connection just finished and is ready to be attached to the server
	[[MojoHTTPServer sharedInstance] addConnection:connectedSocket];
	
	// And we're now done with the stunt socket, so we can go ahead and remove it
	[stuntConnections removeObject:sender];
}

- (void)stuntSocketDidFail:(STUNTSocket *)sender
{
	// Log the connection failure
	NSLog(@"Incoming STUNT connection failed!");
	
	// And we're now done with the stunt socket, so we can go ahead and remove it
	[stuntConnections removeObject:sender];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark STUN Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)stunSocket:(STUNSocket *)sender didSucceed:(AsyncUdpSocket *)socket
{
	// We need to create a Pseudo TCP socket on top of the UDP socket
	PseudoTcp *ptcp = [[[PseudoTcp alloc] initWithUdpSocket:socket] autorelease];
	
	// And we need to start the Pseudo TCP connection
	[ptcp passiveOpen];
	
	// And then we need to disguise the Pseudo TCP socket in an asynchronous
	// wrapper so it can be used just like a TCP AsyncSocket instance.
	PseudoAsyncSocket *connectedSocket = [[[PseudoAsyncSocket alloc] initWithPseudoTcp:ptcp] autorelease];
	
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// Attach the connection to the server
	[[MojoHTTPServer sharedInstance] addConnection:connectedSocket];
	
	// And we're now done with the stun socket, so we can go ahead and remove it
	[stunConnections removeObject:sender];
}

- (void)stunSocketDidFail:(STUNSocket *)sender
{
	// Log the connection failure
	NSLog(@"Incoming STUN connection failed!");
	
	// And we're now done with the stun socket, so we can go ahead and remove it
	[stunConnections removeObject:sender];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark TURN Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)turnSocket:(TURNSocket *)sender didSucceed:(AsyncSocket *)connectedSocket
{
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// The incoming turn connection just finished and is ready to be attached to the server
	[[MojoHTTPServer sharedInstance] addConnection:connectedSocket];
	
	// And we're now done with the turn socket, so we can go ahead and remove it
	[turnConnections removeObject:sender];
}

- (void)turnSocketDidFail:(TURNSocket *)sender
{
	// Log the connection failure
	NSLog(@"Incoming TURN connection failed!");
	
	// And we're now done with the turn socket, so we can go ahead and remove it
	[turnConnections removeObject:sender];
}

@end
