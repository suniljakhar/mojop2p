#import "GatewayHTTPServer.h"
#import "AsyncSocket.h"
#import "RHMutableData.h"
#import "STUNTSocket.h"
#import "MojoXMPPClient.h"
#import "STUNSocket.h"
#import "PseudoTcp.h"
#import "PseudoAsyncSocket.h"
#import "TURNSocket.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 3
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#define WAIT_STUNT  6.0
#define WAIT_STUN   9.0
#define WAIT_TURN   9.0

#define PROTOCOL_NONE   (0 << 0)
#define PROTOCOL_TCP    (1 << 0)
#define PROTOCOL_UDP    (1 << 1)
#define PROTOCOL_PROXY  (1 << 2)

#ifdef CONFIGURATION_DEBUG
  #define ENABLE_STUNT   YES
  #define ENABLE_STUN    YES
  #define ENABLE_TURN    YES
#else
  #define ENABLE_STUNT   YES
  #define ENABLE_STUN    YES
  #define ENABLE_TURN    YES
#endif

#define GatewayHTTPConnectionDidDieNotification  @"GatewayHTTPConnectionDidDie"

@interface GatewayHTTPServer (PrivateAPI)
- (void)performPostInitSetup;
- (void)sendDiscoQuery;
- (void)startSTUNT:(unsigned int)backupPlans;
- (void)startSTUN:(unsigned int)backupPlans;
- (void)startTURN:(unsigned int)backupPlans;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation GatewayHTTPServer

- (id)initWithHost:(NSString *)host port:(UInt16)port
{
	if((self = [super init]))
	{
		// Store the given host/port info
		remoteHost = [host copy];
		remotePort = port;
		
		// Perform all other init tasks
		[self performPostInitSetup];
	}
	return self;
}

- (id)initWithJID:(XMPPJID *)aJID
{
	NSAssert([aJID isMemberOfClass:[XMPPJID class]], @"jid is not of type XMPPJID");
	
	if((self = [super init]))
	{
		// Store the given JID
		jid = [aJID copy];
		
		// Determin if remote host supports STUN
		remoteHostSupportsSTUN = [[[MojoXMPPClient sharedInstance] resourceForJID:jid] stunSupport];
		
		// Start disco query to determine if the remote host supports TURN
		remoteHostSupportsTURN = NO;
		[self sendDiscoQuery];
		
		// Perform all other init tasks
		[self performPostInitSetup];
	}
	return self;
}

- (void)performPostInitSetup
{
	// Create a local socket
	localSocket = [[AsyncSocket alloc] initWithDelegate:self];
	
	// Ensure socket is operating in all common run loop modes
	[localSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// Start listening for connections from localhost
	[localSocket acceptOnAddress:@"localhost" port:0 error:nil];
	
	DDLogVerbose(@"GatewayHTTPServer started on port: %hu", [localSocket localPort]);
	
	// Initialize the various arrays
	connections                 = [[NSMutableArray alloc] initWithCapacity:4];
	unavailableRemoteSockets    = [[NSMutableArray alloc] initWithCapacity:4];
	availableRemoteTcpSockets   = [[NSMutableArray alloc] initWithCapacity:4];
	availableRemoteUdpSockets   = [[NSMutableArray alloc] initWithCapacity:4];
	availableRemoteProxySockets = [[NSMutableArray alloc] initWithCapacity:4];
	stuntSockets                = [[NSMutableArray alloc] initWithCapacity:4];
	stunSockets                 = [[NSMutableArray alloc] initWithCapacity:4];
	turnSockets                 = [[NSMutableArray alloc] initWithCapacity:4];	
	waitStuntTimers             = [[NSMutableArray alloc] initWithCapacity:4];
	waitStunTimers              = [[NSMutableArray alloc] initWithCapacity:4];
	waitTurnTimers              = [[NSMutableArray alloc] initWithCapacity:4];
	
#ifdef CONFIGURATION_DEBUG
	stuntSuccessCount = 0;
	stuntFailureCount = 0;
	stunSuccessCount  = 0;
	stunFailureCount  = 0;
	turnSuccessCount  = 0;
	turnFailureCount  = 0;
#else
	stuntSuccessCount = 0;
	stuntFailureCount = 0;
	stunSuccessCount  = 0;
	stunFailureCount  = 0;
	turnSuccessCount  = 0;
	turnFailureCount  = 0;
#endif
	
	// Register for notifications of closed connections
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(connectionDidDie:)
												 name:GatewayHTTPConnectionDidDieNotification
											   object:nil];
}

/**
 * Standard Deconstructor
**/
- (void)dealloc
{
	DDLogVerbose(@"GatewayHTTPServer: dealloc");
	
	// Unregister for notifications (GatewayHTTPConnectionDidDieNotification)
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Unregister for XMPPClient callbacks
	[[MojoXMPPClient sharedInstance] removeDelegate:self];
	
	NSUInteger i;
	
	// The sockets in our availableRemoteSockets arrays may be retained in multiple places.
	// So when we release the array, the sockets may or may not be immediately dealloced.
	// If they're not dealloced until later, and we're still the socket's delegate, it will cause a crash.
	// So we specifically go through, and unset ourselves as the delegate, and close each socket.
	// We then do the same for the unavailableRemoteSockets array just for good measure.
	
	for(i = 0; i < [availableRemoteTcpSockets count]; i++)
	{
		AsyncSocket *currentSocket = [availableRemoteTcpSockets objectAtIndex:i];
		[currentSocket setDelegate:nil];
		[currentSocket disconnect];
	}
	
	for(i = 0; i < [availableRemoteUdpSockets count]; i++)
	{
		PseudoAsyncSocket *currentSocket = [availableRemoteUdpSockets objectAtIndex:i];
		[currentSocket setDelegate:nil];
		[currentSocket disconnect];
	}
	
	for(i = 0; i < [availableRemoteProxySockets count]; i++)
	{
		AsyncSocket *currentSocket = [availableRemoteProxySockets objectAtIndex:i];
		[currentSocket setDelegate:nil];
		[currentSocket disconnect];
	}
	
	for(i = 0; i < [unavailableRemoteSockets count]; i++)
	{
		AsyncSocket *currentSocket = [unavailableRemoteSockets objectAtIndex:i];
		[currentSocket setDelegate:nil];
		[currentSocket disconnect];
	}
	
	// Any existing STUNT, STUN, or TURN sockets may be holding a reference to us as a delegate
	
	for(i = 0; i < [stuntSockets count]; i++)
	{
		[[stuntSockets objectAtIndex:i] abort];
	}
	
	for(i = 0; i < [stunSockets count]; i++)
	{
		[[stunSockets objectAtIndex:i] abort];
	}
	
	for(i = 0; i < [turnSockets count]; i++)
	{
		[[turnSockets objectAtIndex:i] abort];
	}
	
	// Invalidate all the timers
	
	for(i = 0; i < [waitStuntTimers count]; i++)
	{
		[[waitStuntTimers objectAtIndex:i] invalidate];
	}
	
	for(i = 0; i < [waitStunTimers count]; i++)
	{
		[[waitStunTimers objectAtIndex:i] invalidate];
	}
	
	for(i = 0; i < [waitTurnTimers count]; i++)
	{
		[[waitTurnTimers objectAtIndex:i] invalidate];
	}
	
	// Normal dealloc stuff
	
	[remoteHost release];
	[jid release];
	
	[localSocket setDelegate:nil];
	[localSocket disconnect];
	[localSocket release];
	
	[connections release];
	[unavailableRemoteSockets release];
	[availableRemoteTcpSockets release];
	[availableRemoteUdpSockets release];
	[availableRemoteProxySockets release];
	[stuntSockets release];
	[stunSockets release];
	[turnSockets release];
	[waitStuntTimers release];
	[waitStunTimers release];
	[waitTurnTimers release];
	[uuid release];
	
	[super dealloc];
}

/**
 * Returns the local port that may be used to connect to the gateway server.
**/
- (UInt16)localPort
{
	return [localSocket localPort];
}

/**
 * Sets whether or not the remote host requires a secure SSL/TLS connection.
 * This is set to NO by default.
**/
- (void)setIsSecure:(BOOL)useSSL
{
	isSecure = useSSL;
}

/**
 * Sets the proper authentication for the remote host.
**/
- (void)setUsername:(NSString *)aUsername password:(NSString *)aPassword
{
	if(![username isEqualToString:aUsername])
	{
		[username release];
		username = [aUsername copy];
	}
	if(![password isEqualToString:aPassword])
	{
		[password release];
		password = [aPassword copy];
	}
}

- (BOOL)isSecure
{
	return isSecure;
}

- (NSString *)username
{
	return username;
}

- (NSString *)password
{
	return password;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)sendDiscoQuery
{
	remoteHostSupportsTURN = NO;
	
	CFUUIDRef theUUID = CFUUIDCreate(NULL);
	uuid = (NSString *)CFUUIDCreateString(NULL, theUUID);
	CFRelease(theUUID);
	
	[[MojoXMPPClient sharedInstance] addDelegate:self];
	
	NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
	
	NSXMLElement *iq = [NSXMLElement elementWithName:@"iq"];
	[iq addAttributeWithName:@"type" stringValue:@"get"];
	[iq addAttributeWithName:@"to" stringValue:[jid full]];
	[iq addAttributeWithName:@"id" stringValue:uuid];
	[iq addChild:query];
	
	[[MojoXMPPClient sharedInstance] sendElement:iq];
}

- (void)xmppClient:(XMPPClient *)sender didReceiveIQ:(XMPPIQ *)iq
{
	if(![uuid isEqualToString:[iq elementID]])
	{
		// Doesn't apply to us
		return;
	}
	
	NSXMLElement *query = [iq elementForName:@"query" xmlns:@"http://jabber.org/protocol/disco#info"];
	NSArray *identities = [query elementsForName:@"identity"];
	
	NSUInteger i;
	for(i = 0; i < [identities count] && !remoteHostSupportsTURN; i++)
	{
		NSXMLElement *identity = [identities objectAtIndex:i];
		
		NSString *category = [[identity attributeForName:@"category"] stringValue];
		NSString *type = [[identity attributeForName:@"type"] stringValue];
		
		if([category isEqualToString:@"proxy"] && [type isEqualToString:@"bytestreams"])
		{
			remoteHostSupportsTURN = YES;
		}
	}
	
	// We're no longer interested in XMPP messages
	[[MojoXMPPClient sharedInstance] removeDelegate:self];
	
	if(remoteHostSupportsTURN)
	{
		DDLogVerbose(@"GatewayHTTPServer: Remote host supports TURN");
	}
	else
	{
		DDLogVerbose(@"GatewayHTTPServer: Remote host does NOT support TURN");
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (unsigned int)nextProtocolFromTcp:(BOOL)tcp udp:(BOOL)udp proxy:(BOOL)proxy
{
	tcp   = tcp   && ENABLE_STUNT;
	udp   = udp   && ENABLE_STUN  && remoteHostSupportsSTUN;
	proxy = proxy && ENABLE_TURN  && remoteHostSupportsTURN;
	
	if(!tcp && !udp && !proxy)
	{
		return PROTOCOL_NONE;
	}
	
	UInt32 tcpAttemptCount   = stuntSuccessCount + stuntFailureCount;
	UInt32 udpAttemptCount   = stunSuccessCount  + stunFailureCount;
	UInt32 proxyAttemptCount = turnSuccessCount  + turnFailureCount;
	
	float tcpSuccessRate   = 1.0f;
	float udpSuccessRate   = 1.0f;
	float proxySuccessRate = 1.0f;
	
	if(tcpAttemptCount > 0)
		tcpSuccessRate = (float)stuntSuccessCount / (float)tcpAttemptCount;
	
	if(udpAttemptCount > 0)
		udpSuccessRate = (float)stunSuccessCount / (float)udpAttemptCount;
	
	if(proxyAttemptCount > 0)
		proxySuccessRate = (float)turnSuccessCount / (float)proxyAttemptCount;
	
	// Add exception for tcp and udp if they've only tried and failed once.
	
	if(tcp && (stuntSuccessCount == 0) && (stuntFailureCount == 1))
	{
		tcpSuccessRate = 0.75f;
	}
	
	if(udp && (stunSuccessCount == 0) && (stunFailureCount == 1))
	{
		udpSuccessRate = 0.75f;
	}
	
	// Return the protocol with the highest success rate.
	// In the event of a tie, return the protocol we've tried the least.
	
	// Prevent disabled protocols from winning
	
	if(!tcp)   tcpSuccessRate   = -1.0f;
	if(!udp)   udpSuccessRate   = -1.0f;
	if(!proxy) proxySuccessRate = -1.0f;
	
	// Note: We know at least one of the protocols is enabled.
	// Therefore, at least one of the protocols will have a success rate >= 0.0
	
	if(tcpSuccessRate > udpSuccessRate)
	{
		if(tcpSuccessRate > proxySuccessRate)
		{
			// (tcp > udp) && (tcp > proxy)
			return PROTOCOL_TCP;
		}
		else if(proxySuccessRate > tcpSuccessRate)
		{
			// (proxy > tcp) && (tcp > udp)
			return PROTOCOL_PROXY;
		}
		else
		{
			// (tcp > udp) && (tcp == proxy)
			
			if(tcpAttemptCount <= proxyAttemptCount)
				return PROTOCOL_TCP;
			else
				return PROTOCOL_PROXY;
		}
	}
	else if(udpSuccessRate > tcpSuccessRate)
	{
		if(udpSuccessRate > proxySuccessRate)
		{
			// (udp > tcp) && (udp > proxy)
			return PROTOCOL_UDP;
		}
		else if(proxySuccessRate > udpSuccessRate)
		{
			// (proxy > udp) && (udp > tcp)
			return PROTOCOL_PROXY;
		}
		else
		{
			// (udp > tcp) && (udp == proxy)
			
			if(udpAttemptCount <= proxyAttemptCount)
				return PROTOCOL_UDP;
			else
				return PROTOCOL_PROXY;
		}
	}
	else
	{
		if(proxySuccessRate > udpSuccessRate)
		{
			// (proxy > udp) && (udp == tcp)
			return PROTOCOL_PROXY;
		}
		else if(udpSuccessRate > proxySuccessRate)
		{
			// (udp > proxy) && (udp == tcp)
			
			if(tcpAttemptCount <= udpAttemptCount)
				return PROTOCOL_TCP;
			else
				return PROTOCOL_UDP;
		}
		else
		{
			// tcp == udp == proxy
			
			// Note: It's impossible to get here unless all protocols are enabled.
			
			if(tcpAttemptCount <= udpAttemptCount)
			{
				if(tcpAttemptCount <= proxyAttemptCount)
				{
					// (tcp <= udp) && (tcp <= proxy)
					return PROTOCOL_TCP;
				}
				else
				{
					// (proxy < tcp) && (tcp <= udp)
					return PROTOCOL_PROXY;
				}
			}
			else if(udpAttemptCount <= proxyAttemptCount)
			{
				// (udp < tcp) && (udp <= proxy)
				return PROTOCOL_UDP;
			}
			else
			{
				// (proxy < udp) && (udp < tcp)
				return PROTOCOL_PROXY;
			}
		}
	}
}

/**
 * Begins the process of getting a remote socket for a given connection.
 * Note that the remoteSocket of the connection must be nil in order for it's setRemoteSocket: method to be called.
**/
- (void)requestNewRemoteSocket:(GatewayHTTPConnection *)connection
{
	// Check to see if we have a remoteSocket already available for the connection
	if([availableRemoteTcpSockets count] > 0)
	{
		DDLogInfo(@"GatewayHTTPServer: RECYCLING PREVIOUS CONNECTION! (TCP)");
		
		// Attach socket to connection
		[connection setRemoteSocket:[availableRemoteTcpSockets objectAtIndex:0]];
		
		// Remove socket from our list
		// We only keep a reference to those sockets which are available for use
		[availableRemoteTcpSockets removeObjectAtIndex:0];
	}
	else if([availableRemoteUdpSockets count] > 0)
	{
		DDLogInfo(@"GatewayHTTPServer: RECYCLING PREVIOUS CONNECTION! (UDP)");
		
		// Attach socket to connection
		[connection setRemoteSocket:[availableRemoteUdpSockets objectAtIndex:0]];
		
		// Remove socket from our list
		// We only keep a reference to those sockets which are available for use
		[availableRemoteUdpSockets removeObjectAtIndex:0];
	}
	else if([availableRemoteProxySockets count] > 0)
	{
		DDLogInfo(@"GatewayHTTPServer: RECYCLING PREVIOUS CONNECTION! (PROXY)");
		
		// Attach socket to connection
		[connection setRemoteSocket:[availableRemoteProxySockets objectAtIndex:0]];
		
		// Remove socket from our list
		// We only keep a reference to those sockets which are available for use
		[availableRemoteProxySockets removeObjectAtIndex:0];
	}
	else
	{
		if(remoteHost)
		{
			DDLogInfo(@"GatewayHTTPServer: CREATING NEW CONNECTION");
			
			// Create new remote socket, and connect to the configured host and port
			AsyncSocket *remoteSocket = [[AsyncSocket alloc] initWithDelegate:self];
			
			// Mark the socket as being a direct TCP connection
			[remoteSocket setUserData:PROTOCOL_TCP];
			
			// Ensure the socket is running in all common run loop modes
			[remoteSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
			
			// Store the remote socket
			// Note that it won't be available until after it's connected
			[unavailableRemoteSockets addObject:remoteSocket];
			
			// Start the connection attempt
			// Note that it's important that we do this after adding it to the unavailableRemoteSockets array
			// This is because we need to know this in the onSocketWillConnect: method, which is immediately called.
			[remoteSocket connectToHost:remoteHost onPort:remotePort error:nil];
			
			// And finally, release the remote socket
			// Although it won't actually be released since we added it to the unavailbleRemoteSockets array
			[remoteSocket release];
		}
		else
		{
			// We need to decide which protocols to try
			
			int protocol = [self nextProtocolFromTcp:YES udp:YES proxy:YES];
			
			if(protocol == PROTOCOL_TCP)
			{
				DDLogInfo(@"GatewayHTTPServer: CREATING NEW CONNECTION (STUNT)");
				
				[self startSTUNT:(PROTOCOL_UDP | PROTOCOL_PROXY)];
			}
			else if(protocol == PROTOCOL_UDP)
			{
				DDLogInfo(@"GatewayHTTPServer: CREATING NEW CONNECTION (STUN)");
				
				[self startSTUN:(PROTOCOL_TCP | PROTOCOL_PROXY)];
			}
			else
			{
				DDLogInfo(@"GatewayHTTPServer: CREATING NEW CONNECTION (TURN)");
				
				[self startTURN:(PROTOCOL_TCP | PROTOCOL_UDP)];
			}
		}
	}
}

/**
 * Starts the TCP NAT traversal procedure.
**/
- (void)startSTUNT:(unsigned int)backupProtocols
{
	STUNTSocket *stuntSocket = [[STUNTSocket alloc] initWithJID:jid];
	
	// If the STUNT procedure takes a long time, we'll automatically try something else
	NSTimer *timer = [NSTimer timerWithTimeInterval:WAIT_STUNT
											 target:self
										   selector:@selector(waitStuntTimeout:)
										   userInfo:[NSNumber numberWithUnsignedInt:backupProtocols]
											repeats:NO];
	
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
	[waitStuntTimers addObject:timer];
	
	// Start protocol after starting timer in case it fails immediately
	[stuntSockets addObject:stuntSocket];
	[stuntSocket start:self];
	[stuntSocket release];
}

/**
 * Starts the UDP NAT traversal procedure.
**/
- (void)startSTUN:(unsigned int)backupProtocols
{
	STUNSocket *stunSocket = [[STUNSocket alloc] initWithJID:jid];
	
	// If the STUN procedure takes a long time, we'll automatically try something else
	NSTimer *timer = [NSTimer timerWithTimeInterval:WAIT_STUN
											 target:self
										   selector:@selector(waitStunTimeout:)
										   userInfo:[NSNumber numberWithUnsignedInt:backupProtocols]
											repeats:NO];
	
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
	[waitStunTimers addObject:timer];
	
	// Start protocol after starting timer in case it fails immediately
	[stunSockets addObject:stunSocket];
	[stunSocket start:self];
	[stunSocket release];
}

/**
 * Starts the traversal through proxy procedure.
**/
- (void)startTURN:(unsigned int)backupProtocols
{
	TURNSocket *turnSocket = [[TURNSocket alloc] initWithJID:jid];
	
	// If the TURN procedure takes a long time, we'll automatically try something else
	NSTimer *timer = [NSTimer timerWithTimeInterval:WAIT_TURN
											 target:self
										   selector:@selector(waitTurnTimeout:)
										   userInfo:[NSNumber numberWithUnsignedInt:backupProtocols]
											repeats:NO];
	
	[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
	[waitTurnTimers addObject:timer];
	
	// Start protocol after starting timer in case it fails immediately
	[turnSockets addObject:turnSocket];
	[turnSocket start:self];
	[turnSocket release];
}

/**
 * Called if the STUNT procedure takes too long, or if it fails.
 * This is our cue to try something else.
**/
- (void)waitStuntTimeout:(NSTimer *)aTimer
{
	if([waitStuntTimers count] > 0)
	{
		NSTimer *timer = [waitStuntTimers objectAtIndex:0];
		
		unsigned int backupPlans = [[timer userInfo] unsignedIntValue];
		
		[timer invalidate];
		[waitStuntTimers removeObjectAtIndex:0];
		
		BOOL udp = backupPlans & PROTOCOL_UDP;
		BOOL proxy = backupPlans & PROTOCOL_PROXY;
		
		int nextProtocol = [self nextProtocolFromTcp:NO udp:udp proxy:proxy];
		
		if(nextProtocol == PROTOCOL_UDP)
		{
			[self startSTUN:(proxy ? PROTOCOL_PROXY : PROTOCOL_NONE)];
		}
		else if(nextProtocol == PROTOCOL_PROXY)
		{
			[self startTURN:(udp ? PROTOCOL_UDP : PROTOCOL_NONE)];
		}
	}
}

/**
 * Called if the STUN procedure takes too long, or if it fails.
 * This is our cue to try something else.
**/
- (void)waitStunTimeout:(NSTimer *)aTimer
{
	if([waitStunTimers count] > 0)
	{
		NSTimer *timer = [waitStunTimers objectAtIndex:0];
		
		unsigned int backupPlans = [[timer userInfo] unsignedIntValue];
		
		[timer invalidate];
		[waitStunTimers removeObjectAtIndex:0];
		
		bool tcp = backupPlans & PROTOCOL_TCP;
		bool proxy = backupPlans & PROTOCOL_PROXY;
		
		unsigned int nextProtocol = [self nextProtocolFromTcp:tcp udp:NO proxy:proxy];
		
		if(nextProtocol == PROTOCOL_TCP)
		{
			[self startSTUNT:(proxy ? PROTOCOL_PROXY : PROTOCOL_NONE)];
		}
		else if(nextProtocol == PROTOCOL_PROXY)
		{
			[self startTURN:(tcp ? PROTOCOL_TCP : PROTOCOL_NONE)];
		}
	}
}

/**
 * Called if the TURN procedure takes too long, or if it fails.
 * This is our cue to try something else.
**/
- (void)waitTurnTimeout:(NSTimer *)aTimer
{
	if([waitTurnTimers count] > 0)
	{
		NSTimer *timer = [waitTurnTimers objectAtIndex:0];
		
		unsigned int backupPlans = [[timer userInfo] unsignedIntValue];
		
		[timer invalidate];
		[waitTurnTimers removeObjectAtIndex:0];
		
		bool tcp = backupPlans & PROTOCOL_TCP;
		bool udp = backupPlans & PROTOCOL_UDP;
		
		unsigned int nextProtocol = [self nextProtocolFromTcp:tcp udp:udp proxy:NO];
		
		if(nextProtocol == PROTOCOL_TCP)
		{
			[self startSTUNT:(udp ? PROTOCOL_UDP : PROTOCOL_NONE)];
		}
		else if(nextProtocol == PROTOCOL_UDP)
		{
			[self startSTUN:(tcp ? PROTOCOL_TCP : PROTOCOL_NONE)];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncSocket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
{
	DDLogVerbose(@"GatewayHTTPServer: Accepting new connection");
	
	// Accept the new connection
	GatewayHTTPConnection *newConnection = [[[GatewayHTTPConnection alloc] initWithLocalSocket:newSocket
																					 forServer:self] autorelease];
	[connections addObject:newConnection];
	
	// And get it a remote socket
	[self requestNewRemoteSocket:newConnection];
}

- (BOOL)onSocketWillConnect:(AsyncSocket *)sock
{
	if([unavailableRemoteSockets containsObject:sock])
	{
		if(isSecure)
		{
			DDLogVerbose(@"GatewayHTTPServer: SECURING REMOTE CONNECTION...");
			
			// Connecting to a secure server
			NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:3];
			
			// Use the highest possible security
			[settings setObject:(NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL
						 forKey:(NSString *)kCFStreamSSLLevel];
			
			// We don't care what name is on the certificate
			[settings setObject:[NSNull null]
						 forKey:(NSString *)kCFStreamSSLPeerName];
			
			// Allow self-signed certificates (since almost all Mojo clients will be using them)
			[settings setObject:[NSNumber numberWithBool:YES]
						 forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];
			
			[sock startTLS:settings];
		}
	}
	return YES;
}

/**
 * Called when one of our unavailable sockets becomes available for use.
**/
- (void)onSocket:(id)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	// sock might be AsyncSocket or PseudoAsyncSocket
	
	if([sock isKindOfClass:[PseudoAsyncSocket class]])
	{
		// Ignore - this just means the PsuedoTcp socket has finished the opening handshake
		return;
	}
	
	DDLogVerbose(@"GatewayHTTPServer: CONNECTION READY");
	
	// We need to attach the connected socket to a connection that's waiting for one
	unsigned int i;
	BOOL done = NO;
	
	for(i = 0; i < [connections count] && !done; i++)
	{
		GatewayHTTPConnection *currentGatewayConnection = [connections objectAtIndex:i];
		
		if([currentGatewayConnection remoteSocket] == nil)
		{
			[currentGatewayConnection setRemoteSocket:sock];
			done = YES;
		}
	}
	
	// It's possible that the gateway connection closed before the socket connected
	// If this ever happens, save the connected socket for later use
	if(!done)
	{
		[availableRemoteTcpSockets addObject:sock];
	}
	
	// Remove the socket from our array of unavailable sockets
	[unavailableRemoteSockets removeObject:sock];
}


/**
 * This method is called whenever one of our sockets gets disconnected.
 * It may have been one of our connected, standby sockets, or one of our remote socket connection attempts.
 * We need to remove it from our lists.
**/
- (void)onSocketDidDisconnect:(id)sock
{
	// sock might be AsyncSocket or PseudoAsyncSocket
	
	[unavailableRemoteSockets removeObject:sock];
	[availableRemoteTcpSockets removeObject:sock];
	[availableRemoteUdpSockets removeObject:sock];
	[availableRemoteProxySockets removeObject:sock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark STUNT Socket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when any of our STUNT sockets succeed.
**/
- (void)stuntSocket:(STUNTSocket *)sender didSucceed:(AsyncSocket *)connectedSocket;
{
	DDLogInfo(@"GatewayHTTPServer: CONNECTION READY (STUNT)");
	stuntSuccessCount++;
	
	// Mark the connected socket as being a direct TCP connection
	[connectedSocket setUserData:PROTOCOL_TCP];
	
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// We need to attach the connected socket to a connection that's waiting for one
	unsigned int i;
	BOOL done = NO;
	
	for(i = 0; i < [connections count] && !done; i++)
	{
		GatewayHTTPConnection *currentGatewayConnection = [connections objectAtIndex:i];
		
		if([currentGatewayConnection remoteSocket] == nil)
		{
			[currentGatewayConnection setRemoteSocket:connectedSocket];
			done = YES;
		}
	}
	
	// It's possible that the gateway connection closed before the stunt procedure finished
	// If this ever happens, save the connected socket for later use
	if(!done)
	{
		[connectedSocket setDelegate:self];
		
		[availableRemoteTcpSockets addObject:connectedSocket];
	}
	
	// Remove the stuntSocket from our array of stunt sockets - we no longer need it
	[stuntSockets removeObject:sender];
	
	// Remove the waitStuntTimer
	if([waitStuntTimers count] > 0)
	{
		[[waitStuntTimers objectAtIndex:0] invalidate];
		[waitStuntTimers removeObjectAtIndex:0];
	}
}

/**
 * Called when any of our STUNT sockets fail.
**/
- (void)stuntSocketDidFail:(STUNTSocket *)sender;
{
	DDLogInfo(@"GatewayHTTPServer: STUNT FAILED");
	stuntFailureCount++;
	
	// Remove the stuntSocket from our array of stunt sockets - we no longer need it
	[stuntSockets removeObject:sender];
	
	// Let's try something else
	[self waitStuntTimeout:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark STUN Socket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when any of our STUN sockets succeed.
**/
- (void)stunSocket:(STUNSocket *)sender didSucceed:(AsyncUdpSocket *)socket
{
	DDLogInfo(@"GatewayHTTPServer: CONNECTION READY (STUN)");
	stunSuccessCount++;
	
	// We need to create a Pseudo TCP socket on top of the UDP socket
	PseudoTcp *ptcp = [[[PseudoTcp alloc] initWithUdpSocket:socket] autorelease];
	
	// Start the Pseudo TCP connection to get it going
	[ptcp activeOpen];
	
	// And then we need to disguise the Pseudo TCP socket in an asynchronous
	// wrapper so it can be used just like a TCP AsyncSocket instance.
	PseudoAsyncSocket *connectedSocket = [[[PseudoAsyncSocket alloc] initWithPseudoTcp:ptcp] autorelease];
	
	// Mark the connected socket as being a direct UDP connection
	[connectedSocket setUserData:PROTOCOL_UDP];
	
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// We need to attach the connected socket to a connection that's waiting for one
	unsigned int i;
	BOOL done = NO;
	
	for(i = 0; i < [connections count] && !done; i++)
	{
		GatewayHTTPConnection *currentGatewayConnection = [connections objectAtIndex:i];
		
		if([currentGatewayConnection remoteSocket] == nil)
		{
			[currentGatewayConnection setRemoteSocket:(AsyncSocket *)connectedSocket];
			done = YES;
		}
	}
	
	// It's possible that the gateway connection closed before the stunt procedure finished
	// If this ever happens, save the connected socket for later use
	if(!done)
	{
		[connectedSocket setDelegate:self];
		
		[availableRemoteUdpSockets addObject:connectedSocket];
	}
	
	// Remove the stuntSocket from our array of stunt sockets - we no longer need it
	[stunSockets removeObject:sender];
	
	// Remove the waitStunTimer
	if([waitStunTimers count] > 0)
	{
		[[waitStunTimers objectAtIndex:0] invalidate];
		[waitStunTimers removeObjectAtIndex:0];
	}
}

/**
 * Called when any of our STUN sockets fail.
**/
- (void)stunSocketDidFail:(STUNSocket *)sender
{
	DDLogInfo(@"GatewayHTTPServer: STUN FAILED");
	stunFailureCount++;
	
	// Remove the stunSocket from our array of stun sockets - we no longer need it
	[stunSockets removeObject:sender];
	
	// Let's try something else
	[self waitStunTimeout:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark TURN Socket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when any of our TURN sockets succeed.
**/
- (void)turnSocket:(TURNSocket *)sender didSucceed:(AsyncSocket *)connectedSocket;
{
	DDLogInfo(@"GatewayHTTPServer: CONNECTION READY (TURN)");
	turnSuccessCount++;
	
	// Mark the connected socket as being a proxy connection
	[connectedSocket setUserData:PROTOCOL_PROXY];
	
	// Ensure the connected socket is running in all common run loop modes
	[connectedSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
	
	// We need to attach the connected socket to a connection that's waiting for one
	unsigned int i;
	BOOL done = NO;
	
	for(i = 0; i < [connections count] && !done; i++)
	{
		GatewayHTTPConnection *currentGatewayConnection = [connections objectAtIndex:i];
		
		if([currentGatewayConnection remoteSocket] == nil)
		{
			[currentGatewayConnection setRemoteSocket:connectedSocket];
			done = YES;
		}
	}
	
	// It's possible that the gateway connection closed before the turn procedure finished
	// If this ever happens, save the connected socket for later use
	if(!done)
	{
		[connectedSocket setDelegate:self];
		
		[availableRemoteProxySockets addObject:connectedSocket];
	}
	
	// Remove the sender from our array of turn sockets - we no longer need it
	[turnSockets removeObject:sender];
	
	// Remove the waitTurnTimer
	if([waitTurnTimers count] > 0)
	{
		[[waitTurnTimers objectAtIndex:0] invalidate];
		[waitTurnTimers removeObjectAtIndex:0];
	}
	
	// If this is the one of the first connections, let's try stunt or stun one more time in the background
	if(stuntSuccessCount == 0 && stuntFailureCount == 1)
	{
		[self startSTUNT:PROTOCOL_NONE];
	}
	else if(stunSuccessCount == 0 && stunFailureCount == 1)
	{
		[self startSTUN:PROTOCOL_NONE];
	}
}

/**
 * Called when any of our TURN sockets fail.
**/
- (void)turnSocketDidFail:(TURNSocket *)sender;
{
	DDLogInfo(@"GatewayHTTPServer: TURN FAILED");
	turnFailureCount++;
	
	// Remove the sender from our array of turn sockets - we no longer need it
	[turnSockets removeObject:sender];
	
	// Let's try something else
	[self waitTurnTimeout:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is automatically called when a notification of type GatewayHTTPConnectionDidDieNotification is posted.
 * It allows us to remove the connection from our array.
**/
- (void)connectionDidDie:(NSNotification *)notification
{
	DDLogInfo(@"GatewayHTTPServer: Connection Died");
	
	// Extract the connection that posted the notification
	GatewayHTTPConnection *gatewayConnection = [notification object];
	
	// Check to see if the remoteSocket of the connection is reuseable and still connected
	// If so, then we'll save it for another connection
	
	if([gatewayConnection isRemoteSocketReusable])
	{
		DDLogInfo(@"GatewayHTTPServer: Socket is reusable");
		
		AsyncSocket *remoteSocket = [gatewayConnection remoteSocket];
		if([remoteSocket isConnected])
		{
			DDLogInfo(@"GatewayHTTPServer: Socket is connected");
			
			[remoteSocket setDelegate:self];
			
			if([remoteSocket userData] == PROTOCOL_TCP)
			{
				[availableRemoteTcpSockets addObject:remoteSocket];
			}
			else if([remoteSocket userData] == PROTOCOL_UDP)
			{
				[availableRemoteUdpSockets addObject:remoteSocket];
			}
			else
			{
				[availableRemoteProxySockets addObject:remoteSocket];
			}
		}
	}
	
	// And finally, we can remove the connection from our connections array
	[connections removeObject:gatewayConnection];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Define timeouts
#define FIRST_HEADER_LINE_TIMEOUT  5
#define NO_TIMEOUT                -1

// Define the various tags we'll use to differentiate what it is we're currently downloading
#define HTTP_HEADERS              15
#define HTTP_BODY                 30
#define HTTP_BODY_IGNORE          31
#define HTTP_BODY_CHUNKED         40
#define HTTP_BODY_CHUNKED_IGNORE  41

// Define the various stages of downloading a chunked resource
#define CHUNKED_STAGE_SIZE         1
#define CHUNKED_STAGE_DATA         2
#define CHUNKED_STAGE_FOOTER       3


@implementation GatewayHTTPConnection

/**
 * Sole Constructor
**/
- (id)initWithLocalSocket:(AsyncSocket *)aLocalSocket forServer:(GatewayHTTPServer *)myServer
{
	if((self = [super init]))
	{
		// Store, and take ownership of new local socket
		localSocket = [aLocalSocket retain];
		[localSocket setDelegate:self];
		
		// Store reference to server
		// Note that we do not retain the server. Parents retain their children, children do not retain their parents.
		server = myServer;
		
		// Initialize tracking variables
		isResponseConnectionClose = NO;
		isProcessingRequestOrResponse = NO;
		
		// Initialize request/response tracking variables
		fileSizeInBytes = 0;
		totalBytesReceived = 0;
	}
	return self;
}

/**
 * Standard Deconstructor
**/
- (void)dealloc
{
	if([remoteSocket delegate] == self)
	{
		[remoteSocket setDelegate:nil];
	}
	[remoteSocket release];
	
	[localSocket setDelegate:nil];
	[localSocket disconnect];
	[localSocket release];
	
	if(request)  CFRelease(request);
	if(response) CFRelease(response);
	
	[chunkedData release];
	
	if(auth) CFRelease(auth);
	
	[super dealloc];
}

- (AsyncSocket *)remoteSocket
{
	return remoteSocket;
}

/**
 * This method may be called when:
 * 1) The server has created a remote socket for this connection and is setting it for the first time.
 * 2) We requested a new remote socket (since our old one closed), and the server is now responsding to that request.
**/
- (void)setRemoteSocket:(AsyncSocket *)aRemoteSocket
{
	DDLogVerbose(@"GatewayHTTPConnection: setRemoteSocket");
	
	if(request == NULL)
	{
		// Store and take ownership of the remoteSocket
		remoteSocket = [aRemoteSocket retain];
		[remoteSocket setDelegate:self];
		
		// Now that we have a full connection we can start reading from the local socket
		// Create a new HTTPHeader to hold incoming request, and start reading response
		request = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, YES);
		[localSocket readDataToData:[AsyncSocket CRLFData] withTimeout:FIRST_HEADER_LINE_TIMEOUT tag:HTTP_HEADERS];
	}
	else
	{
		// Store and take ownership of the new remoteSocket
		remoteSocket = [aRemoteSocket retain];
		[remoteSocket setDelegate:self];
		
		// Send new request
		NSData *requestData = [(NSData *)CFHTTPMessageCopySerializedMessage(request) autorelease];
		[remoteSocket writeData:requestData withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
		
		// And start listening for the new response
		if(response) CFRelease(response);
		
		response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
		[remoteSocket readDataToData:[AsyncSocket CRLFData] withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
	}
}

- (BOOL)isRemoteSocketReusable
{
	// If the response from the remote server contained a "Connection: close" header, then it's not reusable
	// Also, if we didn't fully finish processing a request or response, then it's not reusable
	return (!isResponseConnectionClose && !isProcessingRequestOrResponse);
}

- (void)localSocketDidReadData:(NSData *)data withTag:(long)tag
{
	DDLogVerbose(@"GatewayHTTPConnection: localSocketDidReadData:(length=%u) withTag:%d", [data length], tag);
	
	// Update processing variable
	isProcessingRequestOrResponse = YES;
	
	// Forward data from localSocket to remoteSocket
	[remoteSocket writeData:data withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
	
	// We just finished reading an entire line from an HTTP request
	// Append the information to our request
	BOOL result = CFHTTPMessageAppendBytes(request, [data bytes], [data length]);
	if(!result)
	{
		DDLogError(@"GatewayHTTPConnection: Received invalid header line from local socket");
		[localSocket disconnect];
	}
	else if(!CFHTTPMessageIsHeaderComplete(request))
	{
		// Continue reading request from localSocket
		[localSocket readDataToData:[AsyncSocket CRLFData] withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
	}
	else
	{
		DDLogVerbose(@"GatewayHTTPConnection: Finished reading local header");
		
		// Start reading in the response from the remote socket
		response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
		[remoteSocket readDataToData:[AsyncSocket CRLFData] withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
	}
}

- (void)localSocketDidDisconnect
{
	DDLogInfo(@"GatewayHTTPConnection: localSocketDidDisconnect");
	
	[remoteSocket setDelegate:nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:GatewayHTTPConnectionDidDieNotification
														object:self];
}

- (void)remoteSocketDidReadData:(NSData *)data withTag:(long)tag
{
	DDLogVerbose(@"GatewayHTTPConnection: remoteSocketDidReadData:(length=%u) withTag:%d", [data length], tag);
	
	BOOL downloadComplete = NO;
	
	// Sanity check:
	// Theoretically, this method should never get called unless we've called read on the remote socket.
	// However, if something goes wrong (and crash logs have shown it happens) then this method may get called
	// due to previously queued reads on the remote socket before it was assigned to us.
	// If this ever happens, we can no longer trust the remote socket, and we have no choice but to abort.
	if(response == NULL)
	{
		[remoteSocket disconnect];
		return;
	}
	
	if(tag == HTTP_HEADERS)
	{
		// Append the data to our http message
		BOOL result = CFHTTPMessageAppendBytes(response, [data bytes], [data length]);
		if(!result)
		{
			DDLogError(@"GatewayHTTPConnection: Received invalid header line from remote socket");
			[remoteSocket disconnect];
		}
		else if(!CFHTTPMessageIsHeaderComplete(response))
		{
			// Continue reading response from remote socket
			[remoteSocket readDataToData:[AsyncSocket CRLFData] withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
		}
		else
		{
			DDLogVerbose(@"GatewayHTTPConnection: Finished reading remote header");
			
			// Extract the http status code
			CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(response);
			
			// Extract the Content-Length and/or Transfer-Encoding so we know how to read the response
			NSString *contentLength, *transferEncoding;
			
			contentLength = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Content-Length"));
			[contentLength autorelease];
			
			fileSizeInBytes = (unsigned)[contentLength intValue];
			
			transferEncoding = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Transfer-Encoding"));
			[transferEncoding autorelease];
			
			usingChunkedTransfer = [transferEncoding isEqualToString:@"chunked"];
			
			// Check for Connection: close header
			NSString *connection;
			
			connection = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Connection"));
			[connection autorelease];
			
			isResponseConnectionClose = [connection isEqualToString:@"close"];
			
			// Now decide what to do based on the status code we received...
			if(statusCode == 401 && auth == NULL)
			{
				// Create an authentication object from the given response
				// We'll use this to provide proper authentication for each subsequent request
				
				// There is a bug nestled in CFHTTPAuthenticationCreateFromResponse method.
				// Essentially, it calls CFHTTPMessageCopyURL and passes it the response.
				// Of course, there is no URL request in the response, and the method causes a crash (brilliant).
				// This is a known bug, and has already been reported to Apple.
				// The only known workaround is to directly set the request URL in the response.
				NSURL *requestURL = [(NSURL *)CFHTTPMessageCopyRequestURL(request) autorelease];
				if([requestURL host] == nil)
				{
					NSString *host = [(NSString *)CFHTTPMessageCopyHeaderFieldValue(request, CFSTR("Host")) autorelease];
					NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", host]];
					
					requestURL = [NSURL URLWithString:[requestURL relativeString] relativeToURL:baseURL];
				}
				_CFHTTPMessageSetResponseURL(response, (CFURLRef)requestURL);
				
				auth = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, response);
				
				intercepting = ([server username] && [server password]);
			}
			else
			{
				intercepting = NO;
			}
			
			if(!intercepting)
			{
				DDLogVerbose(@"GatewayHTTPConnection: forwarding header response to local socket");
				
				// We're not intercepting the response, so forward the entire thing to the local socket
				NSData *responseData = [(NSData *)CFHTTPMessageCopySerializedMessage(response) autorelease];
				[localSocket writeData:responseData withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
			}
			
			// And start reading in the body of the response if needed
			if(fileSizeInBytes > 0)
			{
				totalBytesReceived = 0;
				
				if(intercepting)
					[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:HTTP_BODY_IGNORE];
				else
					[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:HTTP_BODY];
			}
			else if(usingChunkedTransfer)
			{
				totalBytesReceived = 0;
				chunkedTransferStage = CHUNKED_STAGE_SIZE;
				chunkedData = [[NSMutableData alloc] init];
				
				if(intercepting)
					[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:HTTP_BODY_CHUNKED_IGNORE];
				else
					[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:HTTP_BODY_CHUNKED];
			}
			else
			{
				// There is no message body
				downloadComplete = YES;
			}
		}
	}
	else if(tag == HTTP_BODY || tag == HTTP_BODY_IGNORE)
	{
		if(tag == HTTP_BODY)
		{
			// Immediately forward the data to the local connection
			[localSocket writeData:data withTimeout:NO_TIMEOUT tag:HTTP_BODY];
		}
		
		// We're downloading the data as it becomes available.
		// We need to keep track of how much we've received so we know when the download is complete.
		totalBytesReceived += [data length];
		
		if(totalBytesReceived < fileSizeInBytes)
		{
			[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:HTTP_BODY];
		}
		else
		{
			downloadComplete = YES;
		}
	}
	else if(tag == HTTP_BODY_CHUNKED || tag == HTTP_BODY_CHUNKED_IGNORE)
	{
		if(tag == HTTP_BODY_CHUNKED)
		{
			// Immediately forward the data to the local connection
			[localSocket writeData:data withTimeout:NO_TIMEOUT tag:HTTP_BODY_CHUNKED];
		}
		
		[chunkedData appendData:data];
		
		BOOL doneProcessing = NO;
		while(!doneProcessing)
		{
			if(chunkedTransferStage == CHUNKED_STAGE_SIZE)
			{
				// We need to read in a line with the size of the chunk data (which is in hex).
				// The chunk size is possibly followed by a semicolon and extra parameters that can be ignored,
				// and ending with a CRLF
				NSRange range = [chunkedData rangeOfData:[AsyncSocket CRLFData]];
				
				if(range.length > 0)
				{
					// Extract the chunkSize
					NSString *str = [chunkedData stringValueWithRange:NSMakeRange(0, range.location + range.length)];
					chunkSize = strtol([str UTF8String], NULL, 16);
					
					// Trim the line from the data
					[chunkedData trimStart:(range.location + range.length)];
					
					if(chunkSize > 0)
					{
						chunkedTransferStage = CHUNKED_STAGE_DATA;
					}
					else
					{
						chunkedTransferStage = CHUNKED_STAGE_FOOTER;
					}
				}
				else
				{
					doneProcessing = YES;
				}
			}
			else if(chunkedTransferStage == CHUNKED_STAGE_DATA)
			{
				// Don't forget about the trailing CFLF at the end of the data
				if([chunkedData length] >= chunkSize + 2)
				{
					[chunkedData trimStart:(chunkSize + 2)];
					chunkedTransferStage = CHUNKED_STAGE_SIZE;
				}
				else
				{
					doneProcessing = YES;
				}
			}
			else if(chunkedTransferStage == CHUNKED_STAGE_FOOTER)
			{
				// The data is either a footer (ending with CRLF), or an empty line (single CRLF)
				NSRange range = [chunkedData rangeOfData:[AsyncSocket CRLFData]];
				
				if(range.length > 0)
				{
					[chunkedData trimStart:(range.location + range.length)];
					
					if(range.location == 0 && range.length == 2)
					{
						doneProcessing = YES;
						downloadComplete = YES;
					}
					else
					{
						// We currently don't care about footers, because we're not going to use them for anything.
						// If we did care about them, we could parse them out (ignoring trailing CRLF),
						// and use CFHTTPMessageSetHeaderFieldValue to add them to the header.
					}
				}
				else
				{
					doneProcessing = YES;
				}
			}
		}
		
		if(!downloadComplete)
		{
			// Continue reading data until we've finished reading in the response
			[remoteSocket readDataWithTimeout:NO_TIMEOUT tag:tag];
		}
	}
	
	if(downloadComplete)
	{
		if(intercepting)
		{
			// Update request with proper credentials
			NSString *username = [server username];
			NSString *password = [server password];
			
			CFHTTPMessageApplyCredentials(request, auth, (CFStringRef)username, (CFStringRef)password, NULL);
						
			if(isResponseConnectionClose)
			{
				// Our remote connection won't handle another request
				// We'll have to get a new remote connection
				[remoteSocket setDelegate:nil];
				[remoteSocket disconnect];
				[remoteSocket release];
				remoteSocket = nil;
				
				[server requestNewRemoteSocket:self];
			}
			else
			{
				// Send new request
				NSData *requestData = [(NSData *)CFHTTPMessageCopySerializedMessage(request) autorelease];
				[remoteSocket writeData:requestData withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
				
				// And start listening for the new response
				if(response) CFRelease(response);
				
				response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
				[remoteSocket readDataToData:[AsyncSocket CRLFData] withTimeout:NO_TIMEOUT tag:HTTP_HEADERS];
			}
		}
		else
		{
			// Update processing variable
			isProcessingRequestOrResponse = NO;
			
			// Reset local variables to free up memory
			if(auth) CFRelease(auth);
			if(request) CFRelease(request);
			if(response) CFRelease(response);
			
			auth = NULL;
			request = NULL;
			response = NULL;
			
			[chunkedData release];
			chunkedData = nil;
			
			// And start listening for another possible request from the local socket
			request = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, YES);
			[localSocket readDataToData:[AsyncSocket CRLFData] withTimeout:FIRST_HEADER_LINE_TIMEOUT tag:HTTP_HEADERS];
		}
	}
}

- (void)remoteSocketDidDisconnect
{
	DDLogInfo(@"GatewayHTTPConnection: remoteSocketDidDisconnect");
	
	[localSocket setDelegate:nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:GatewayHTTPConnectionDidDieNotification
														object:self];
}

- (void)onSocket:(id)sock didReadData:(NSData*)data withTag:(long)tag
{
	// sock might be AsyncSocket or PseudoAsyncSocket
	
	if(sock == localSocket)
		[self localSocketDidReadData:data withTag:tag];
	else
		[self remoteSocketDidReadData:data withTag:tag];
}

- (void)onSocketDidDisconnect:(id)sock
{
	// sock might be AsyncSocket or PseudoAsyncSocket
	
	if(sock == localSocket)
		[self localSocketDidDisconnect];
	else
		[self remoteSocketDidDisconnect];
}

@end
