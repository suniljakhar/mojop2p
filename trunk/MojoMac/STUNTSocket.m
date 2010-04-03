/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "STUNTSocket.h"
#import "STUNTUtilities.h"
#import "AsyncSocket.h"
#import "MojoXMPPClient.h"
#import "HelperAppDelegate.h"
#import "SSCrypto.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <TCMPortMapper/TCMPortMapper.h>

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 3
#endif
#include "DDLog.h"

// STUNT protocol version
#define STUNT_VERSION  @"1.1"

// Common states
#define STATE_INIT                  0

// Active Endpoint states
#define STATE_AE_START             10
#define STATE_AE_INVITE_SENT       11
#define STATE_AE_ACCEPT_RECEIVED   12
#define STATE_AE_CALLBACK_SENT     13
#define STATE_AE_SWAP_RECEIVED     14
#define STATE_AE_I_VALIDATION      16
#define STATE_AE_O_VALIDATION      17
#define STATE_AE_DONE              18
#define STATE_AE_FAILURE           19

// Passive Endpoint states
#define STATE_PE_START             20
#define STATE_PE_ACCEPT_SENT       21
#define STATE_PE_CALLBACK_RECEIVED 22
#define STATE_PE_SWAP_SENT         23
#define STATE_PE_I_VALIDATION      26
#define STATE_PE_O_VALIDATION      27
#define STATE_PE_DONE              28
#define STATE_PE_FAILURE           29

// URLs to extract external information
#define URL_IP_PORT_1  @"http://www.deusty.com/utilities/getMyIPAndPort.php"
#define URL_IP_PORT_2  @"http://www.robbiehanson.com:8080/utilities/getMyIPAndPort.php"

// Number of connection attempts
// A single attempt includes one run of the STUNT protocol as an active endpoint and one run as a passive endpoint
#define MAX_ATTEMPTS  2

// Define timeouts (In floating point format representing seconds)

// Timeout for a direct connection (one made without first "punching a hole" in the router)
#define TIMEOUT_PRE_SYN   0.75

// Timeout for an indirect connection (one made after "punching a hole" in the router)
#define TIMEOUT_POST_SYN  1.50

// Timeout for the entire STUNT procedure
// This ensures that in the event a peer crashes, the STUNTSocket object won't reside in memory forever
#define TIMEOUT_TOTAL    20.00

// Read and write validation must be stored for each socket
// We store this within the socket's userData variable
enum SocketValidationFlags
{
	kReadValidationComplete   = 1 << 0,
	kWriteValidationComplete  = 1 << 1,
};

// Declare private methods
@interface STUNTSocket (PrivateAPI)
- (void)performPostInitSetup;
- (BOOL)handleStuntValidation:(NSString *)hash fromSocket:(AsyncSocket *)sock;
- (void)maybeValidateP2PConnection:(AsyncSocket *)sock;
- (void)startP2PValidation:(AsyncSocket *)sock;
- (void)skipP2PValidation:(AsyncSocket *)sock;
- (void)maybeValidateC2SConnection:(AsyncSocket *)sock;
- (void)finishC2SValidation:(AsyncSocket *)sock;
- (void)succeed:(AsyncSocket *)sock;
- (void)fail;
- (void)cleanup;
@end

// Notes:
// 
// asock: Outgoing connection to remote users' server
// bsock: Outgoing connection to remote users' psock
// psock: Socket used to accept connections
// qsock: Incoming connection accepted from psock
// rsock: Incoming connection accepted from server
// fsock: Reference to socket that succeeded

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNTSocket

static NSMutableDictionary *existingStuntSockets;

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
		existingStuntSockets = [[NSMutableDictionary alloc] init];
	}
}

/**
 * Returns whether or not the given message is a new start stunt message,
 * and should therefore be used to create and start a new stunt socket.
**/
+ (BOOL)isNewStartStuntMessage:(XMPPMessage *)msg
{
	if([STUNTMessage isStuntInviteMessage:msg])
	{
		NSString *uuid = [msg elementID];
		
		if([existingStuntSockets objectForKey:uuid])
			return NO;
		else
			return YES;
	}
	return NO;
}

/**
 * This method is called whenver our Mojo HTTP server receives a STUNT validation request.
 * This means the other client was able to directly connect to our HTTP server,
 * and is looking to validate the connection by making sure they connected to us, and not an imposter.
 *
 * Returns YES if it is determined the validation is for an existing STUNTSocket,
 * and the socket has taken ownership of the socket.
 * Returns NO otherwise.
**/
+ (BOOL)handleSTUNTRequest:(CFHTTPMessageRef)request fromSocket:(AsyncSocket *)sock
{
	NSString *hash = [(NSString *)CFHTTPMessageCopyHeaderFieldValue(request, CFSTR("Validation")) autorelease];
	
	if(hash == nil) return NO;
	
	NSArray *stuntSockets = [existingStuntSockets allValues];
	
	int i;
	for(i = 0; i < [stuntSockets count]; i++)
	{
		STUNTSocket *stuntSocket = [stuntSockets objectAtIndex:i];
		
		if([stuntSocket handleStuntValidation:hash fromSocket:sock])
		{
			return YES;
		}
	}
	
	return NO;
}

static NSString *StringFromState(int state)
{
	switch(state)
	{
		case STATE_INIT                 : return @"STATE_INIT";
		
		case STATE_AE_START             : return @"STATE_AE_START";
		case STATE_AE_INVITE_SENT       : return @"STATE_AE_INVITE_SENT";
		case STATE_AE_ACCEPT_RECEIVED   : return @"STATE_AE_ACCEPT_RECEIVED";
		case STATE_AE_CALLBACK_SENT     : return @"STATE_AE_CALLBACK_SENT";
		case STATE_AE_SWAP_RECEIVED     : return @"STATE_AE_SWAP_RECEIVED";
		case STATE_AE_I_VALIDATION      : return @"STATE_AE_I_VALIDATION";
		case STATE_AE_O_VALIDATION      : return @"STATE_AE_O_VALIDATION";
		case STATE_AE_DONE              : return @"STATE_AE_DONE";
		case STATE_AE_FAILURE           : return @"STATE_AE_FAILURE";
		
		case STATE_PE_START             : return @"STATE_PE_START";
		case STATE_PE_ACCEPT_SENT       : return @"STATE_PE_ACCEPT_SENT";
		case STATE_PE_CALLBACK_RECEIVED : return @"STATE_PE_CALLBACK_RECEIVED";
		case STATE_PE_SWAP_SENT         : return @"STATE_PE_SWAP_SENT";
		case STATE_PE_I_VALIDATION      : return @"STATE_PE_I_VALIDATION";
		case STATE_PE_O_VALIDATION      : return @"STATE_PE_O_VALIDATION";
		case STATE_PE_DONE              : return @"STATE_PE_DONE";
		case STATE_PE_FAILURE           : return @"STATE_PE_FAILURE";
	}
	
	return @"STATE_UNKNOWN";
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes a new STUNT socket to create a TCP connection by traversing NAT's and/or firewalls.
 * This constructor configures the object to be the client connecting to a server.
 * Therefore it will start out life as the Active Endpoint.
**/
- (id)initWithJID:(XMPPJID *)aJID
{
	if((self = [super init]))
	{
		// Retain a references to the JID
		jid = [aJID retain];
		
		// Create a uuid to be used as the id for all messages in the stunt communication
		// This helps differentiate various stunt messages between various stunt sockets
		// Relying only on JID's is troublesome, because client A could be initiating a connection to server B,
		// while at the same time client B could be initiating a connection to server A.
		// So an incoming connection from JID clientB@deusty.com/home would be for which stunt socket?
		CFUUIDRef theUUID = CFUUIDCreate(NULL);
		uuid = (NSString *)CFUUIDCreateString(NULL, theUUID);
		CFRelease(theUUID);
		
		// Setup initial state for a client connection
		state = STATE_INIT;
		isClient = YES;
		
		// Try to extract stunt version from txt record in presence
		float stuntVersion = [[[MojoXMPPClient sharedInstance] resourceForJID:jid] stuntVersion];
		
		// The returned stuntVersion will always be at least 1.0,
		// even if the txt record didn't contain a stunt version.
		// It's possible their stunt version is actually 1.1, so we ignore everything but 1.1 and higher.
		
		if(stuntVersion >= 1.1f)
		{
			remote_stuntVersion = [[NSString alloc] initWithFormat:@"%f", stuntVersion];
		}
		
		DDLogVerbose(@"Creating new STUNTSocket to %@", jid);
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Initializes a new STUNT socket to create a TCP connection by traversing NAT's and/or firewalls.
 * This constructor configures the object to be the server accepting a connection from a client,
 * and will thus start out as the passive endpoint.
**/
- (id)initWithStuntMessage:(XMPPMessage *)message
{
	if((self = [super init]))
	{
		// Store a copy of the JID
		jid = [[message from] retain];
		
		// Store a copy of the ID (which will be our uuid)
		uuid = [[message elementID] copy];
		
		// Setup initial state for a server connection
		state = STATE_INIT;
		isClient = NO;
		
		// Extract information from the stunt invite message
		STUNTMessage *stuntMessage = [STUNTMessage messageFromMessage:message];
		
		remote_stuntVersion  = [[stuntMessage version] copy];
		remote_externalIP    = [[stuntMessage ip4] copy];
		remote_serverPort    = [stuntMessage serverPort];
		remote_predictedPort = [stuntMessage predictedPort];
		
		DDLogVerbose(@"Creating new STUNTSocket from %@", jid);
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Common initialization tasks shared by all init methods.
**/
- (void)performPostInitSetup
{
	// Initialize stunt logger
	logger = [[STUNTLogger alloc] initWithSTUNTUUID:uuid version:STUNT_VERSION];
	
	// Add notifications for the port mapper
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(portMappingDidChange:)
												 name:TCMPortMappingDidChangeMappingStatusNotification
											   object:nil];
	
	// We want to add this new stunt socket to the list of existing sockets.
	// This gives us a central repository of stunt socket objects that we can easily query.
	[existingStuntSockets setObject:self forKey:uuid];
}

/**
 * Standard deconstructor.
 * Release any objects we may have retained.
 * These objects should all be defined in the header.
**/
- (void)dealloc
{
	DDLogVerbose(@"Destroying %@", self);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[jid release];
	[uuid release];
	[portMapping release];
	[local_externalIP release];
	[remote_externalIP release];
	
	if([asock delegate] == self) [asock setDelegate:nil];
	if([bsock delegate] == self) [bsock setDelegate:nil];
	if([psock delegate] == self) [psock setDelegate:nil];
	if([qsock delegate] == self) [qsock setDelegate:nil];
	if([rsock delegate] == self) [rsock setDelegate:nil];
	if([fsock delegate] == self) [fsock setDelegate:nil];
	
	[asock release];
	[bsock release];
	[psock release];
	[qsock release];
	[rsock release];
	[fsock release];
	
	[logger release];
	[startTime release];
	[finishTime release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Correspondence Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)start:(id)theDelegate
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	if(state != STATE_INIT)
	{
		// We've already started the stunt procedure
		return;
	}
	
	// Set reference to delegate
	// Note that we do NOT retain the delegate
	delegate = theDelegate;
	
	// Update state and initialize attempt count
	// Note: Only the client manages the attempt count - it should always be zero for non-client
	if(isClient)
	{
		state = STATE_AE_START;
		attemptCount = 1;
	}
	else
	{
		state = STATE_PE_START;
		attemptCount = 0;
	}
	
	// Add self as xmpp delegate so we'll get stunt message responses
	[[MojoXMPPClient sharedInstance] addDelegate:self];
	
	// Start the timer to calculate how long the procedure takes
	startTime = [[NSDate alloc] init];
	
	// Start port mapping procedure
	local_serverPort = [[NSApp delegate] serverPortNumber];
	local_mappedServerPort = 0;
	
	NSString *mappingProtocol = [[TCMPortMapper sharedInstance] mappingProtocol];
	
	if([mappingProtocol isEqualToString:TCMNATPMPPortMapProtocol])
	{
		portMapping = [[TCMPortMapping alloc] initWithLocalPort:local_serverPort
											desiredExternalPort:[STUNTUtilities randomPortNumber]
											  transportProtocol:TCMPortMappingTransportProtocolTCP
													   userInfo:nil];
		
		[[TCMPortMapper sharedInstance] addPortMapping:portMapping];
	}
	else
	{
		BOOL alreadySetup = [[NSApp delegate] addServerPortMapping];
		
		if(alreadySetup)
		{
			[logger setPortMappingAvailable:YES];
			[logger setPortMappingProtocol:[[TCMPortMapper sharedInstance] mappingProtocol]];
			
			// The external port is almost guaranteed to be the server port, but we'll save it just in case.
			// Note that we're NOT setting the local_mappedServerPort here.
			// We use local_mappedServerPort to determine if we created the mapping or if the AppDelegate did.
			local_serverPort = [[[NSApp delegate] serverPortMapping] externalPort];
		}
	}
	
	NSString *hardwareAddr = [[TCMPortMapper sharedInstance] routerHardwareAddress];
	NSString *routerManufacturer = [TCMPortMapper manufacturerForHardwareAddress:hardwareAddr];
	
	[logger setRouterManufacturer:routerManufacturer];
	
	// Start opportunistic direct connection attempts if we started life with an incoming invite message
	if(!isClient)
	{
		if(remote_serverPort > 0)
		{
			asock = [[AsyncSocket alloc] initWithDelegate:self];
			[asock connectToHost:remote_externalIP onPort:remote_serverPort error:nil];
			
			DDLogVerbose(@"STUNTSocket: attempting connection to host:%@ port:%i",
						 remote_externalIP, remote_serverPort);
		}
		
		if(remote_predictedPort > 0)
		{
			bsock = [[AsyncSocket alloc] initWithDelegate:self];
			[bsock connectToHost:remote_externalIP onPort:remote_predictedPort error:nil];
			
			DDLogVerbose(@"STUNTSocket: attempting connection to host:%@ port:%i",
						 remote_externalIP, remote_predictedPort);
		}
		
	}
	
	// Fork off background thread to perform port prediction
	[NSThread detachNewThreadSelector:@selector(portPredictionThread) toTarget:self withObject:nil];
	
	// Schedule timeout timer to cancel the stunt procedure
	// This ensures that, in the event of network error or crash,
	// the STUNTSocket object won't remain in memory forever, and will eventually fail
	[NSTimer scheduledTimerWithTimeInterval:TIMEOUT_TOTAL
									 target:self
								   selector:@selector(doTotalTimeout:)
								   userInfo:nil
									repeats:NO];
}

/**
 * This method returns the UUID (Universally Unique Identifier) that is associated with this StuntSocket instance.
 * This is the value that will be used as the ID attribute of all outgoing and incoming messages associated
 * with this StuntSocket.
 * It may be used to map incoming XMPP messages to the proper StuntSocket.
**/
- (NSString *)uuid
{
	return uuid;
}

/**
 * Returns the type of connection
 * YES for a client connection to a server, NO for a server connection from a client.
**/
- (BOOL)isClient
{
	return isClient;
}

/**
 * This is actually a private method.
**/
- (BOOL)isActiveEndpoint
{
	return (state < STATE_PE_START);
}

/**
 * Aborts the STUNT connection attempt.
 * The status will be changed to failure, and no notifications will be posted.
**/
- (void)abort
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	if(state != STATE_INIT)
	{
		// The only thing we really have to do here is move the state to failure.
		// This simple act should prevent any further action from being taken in this STUNTSocket object,
		// since every action is dictated based on the current state.
		
		if(state <= STATE_AE_FAILURE)
			state = STATE_AE_FAILURE;
		else
			state = STATE_PE_FAILURE;
		
		// And don't forget to cleanup after ourselves
		[self cleanup];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Communication
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Handles sending of a stunt message.
**/
- (void)sendStuntMessage:(STUNTMessage *)message
{
	[[MojoXMPPClient sharedInstance] sendElement:[message xmlElement]];
}

/**
 * This method is called by the XMPPClient whenever a message is sent to us.
**/
- (void)xmppClient:(XMPPClient *)sender didReceiveMessage:(XMPPMessage *)msg
{
	// Check to see if the message is for us
	if(![uuid isEqualToString:[msg elementID]])
	{
		// Message doesn't apply to us
		// It's not a stunt message or it's for another stunt socket
		return;
	}
	
	STUNTMessage *message = [STUNTMessage messageFromMessage:msg];
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:@"%@, message=%@", StringFromState(state), [message type]];
	
	if(state == STATE_AE_INVITE_SENT)
	{
		if([[message type] isEqualToString:@"accept"])
		{
			// We should now be able to extract the server's external IP address and external port.
			// And then we're ready to try a direct connection to the server.
			// If the server is behind a NAT this connection will probably fail.
			
			[remote_stuntVersion release];
			[remote_externalIP release];
			
			remote_stuntVersion = [[message version] copy];
			remote_externalIP = [[message ip4] copy];
			remote_predictedPort = [message predictedPort];
			
			// Update the state
			state = STATE_AE_ACCEPT_RECEIVED;
			
			// Close down psock - the socket we were accepting connections on
			[psock setDelegate:nil];
			[psock disconnect];
			[psock release];
			psock = nil;
			
			// Setup connection, and attempt to connect.
			// Note that we need to use the AsyncSocket connectToAddress:error: method
			// so we can get low-level access to the socket, and bind it to our local port.
			
			DDLogVerbose(@"Attempting connection to:%@:%i on localhost:%i",
						 remote_externalIP, remote_predictedPort, local_internalPort);
			
			struct in_addr netAddr;
			inet_pton(AF_INET, [remote_externalIP UTF8String], &netAddr);
			
			struct sockaddr_in remoteAddr;
			remoteAddr.sin_len    = sizeof(struct sockaddr_in);
			remoteAddr.sin_family = AF_INET;
			remoteAddr.sin_port   = htons(remote_predictedPort);
			remoteAddr.sin_addr   = netAddr;
			memset(&(remoteAddr.sin_zero), 0, sizeof(remoteAddr.sin_zero));
			
			NSData *remoteAddrData = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sin_len];
			
			bsock = [[AsyncSocket alloc] initWithDelegate:self];
			[bsock connectToAddress:remoteAddrData error:nil];
			
			// Schedule timeout timer to cancel connection attempt
			[NSTimer scheduledTimerWithTimeInterval:TIMEOUT_PRE_SYN
											 target:self
										   selector:@selector(doCallbackTimeout:)
										   userInfo:nil
											repeats:NO];
		}
		else
		{
			// We received an error message
			if([message errorMessage])
			{
				[logger setFailureReason:[NSString stringWithFormat:@"RCV: %@", [message errorMessage]]];
			}
			else
			{
				NSString *format = @"Expecting accept message, received '%@' message";
				NSString *reason = [NSString stringWithFormat:format, [message type]];
				[logger setFailureReason:reason]; 
			}
			[self fail];
		}
	}
	else if(state == STATE_PE_ACCEPT_SENT)
	{
		if([[message type] isEqualToString:@"callback"])
		{
			// The active endpoint tried to connect to us, but the connection timed out
			// Thus, it's router has seen an outgoing SYN, and may accept an incoming SYN at this point
			// The active endpoint is accepting connections, and waiting for us to connect
			
			// Update the state
			state = STATE_PE_CALLBACK_RECEIVED;
			
			// Close down asock - connection attempt to server port (if it's still waiting for a SYN ACK)
			[asock setDelegate:nil];
			[asock disconnect];
			[asock release];
			asock = nil;
			
			// Close down bsock - connection attempt to external port (if it's still waiting for a SYN ACK)
			[bsock setDelegate:nil];
			[bsock disconnect];
			[bsock release];
			bsock = nil;
			
			// Close down psock - the socket we were accepting connections on
			[psock setDelegate:nil];
			[psock disconnect];
			[psock release];
			psock = nil;
			
			// Setup connection, and attempt to connect.
			// Note that we need to use the AsyncSocket connectToAddress:error: method
			// so we can get low-level access to the socket, and bind it to our local port.
			
			DDLogVerbose(@"Attempting connection to:%@:%i on localhost:%i", 
						 remote_externalIP, remote_predictedPort, local_internalPort);
			
			struct in_addr netAddr;
			inet_pton(AF_INET, [remote_externalIP UTF8String], &netAddr);
			
			struct sockaddr_in remoteAddr;
			remoteAddr.sin_len    = sizeof(struct sockaddr_in);
			remoteAddr.sin_family = AF_INET;
			remoteAddr.sin_port   = htons(remote_predictedPort);
			remoteAddr.sin_addr   = netAddr;
			memset(&(remoteAddr.sin_zero), 0, sizeof(remoteAddr.sin_zero));
			
			NSData *remoteAddrData = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sin_len];
			
			bsock = [[AsyncSocket alloc] initWithDelegate:self];
			[bsock connectToAddress:remoteAddrData error:nil];
			
			// Schedule timeout timer to cancel connection attempt
			[NSTimer scheduledTimerWithTimeInterval:TIMEOUT_POST_SYN
											 target:self
										   selector:@selector(doSwapTimeout:)
										   userInfo:nil
											repeats:NO];
		}
		else
		{
			// We received an error message
			if([message errorMessage])
			{
				[logger setFailureReason:[NSString stringWithFormat:@"RCV: %@", [message errorMessage]]];
			}
			else
			{
				NSString *format = @"Expecting callback message, received '%@' message";
				NSString *reason = [NSString stringWithFormat:format, [message type]];
				[logger setFailureReason:reason]; 
			}
			[self fail];
		}
	}
	else if(state == STATE_AE_CALLBACK_SENT)
	{
		if([[message type] isEqualToString:@"swap"])
		{
			// We're going to be switching over, and becoming the passive endpoint
			// All we need to do now is wait for the invite messsage
			
			// And we can close our accept socket
			[psock setDelegate:nil];
			[psock disconnect];
			[psock release];
			psock = nil;
			
			// Update state
			state = STATE_AE_SWAP_RECEIVED;
			
			DDLogVerbose(@"STUNTSocket: Received swap message. Waiting for invite message...");
		}
		else
		{
			// We received an error message
			if([message errorMessage])
			{
				[logger setFailureReason:[NSString stringWithFormat:@"RCV: %@", [message errorMessage]]];
			}
			else
			{
				NSString *format = @"Expecting swap message, received '%@' message";
				NSString *reason = [NSString stringWithFormat:format, [message type]];
				[logger setFailureReason:reason]; 
			}
			[self fail];
		}
	}
	else if(state == STATE_AE_SWAP_RECEIVED)
	{
		if([[message type] isEqualToString:@"invite"])
		{
			// Update state
			state = STATE_PE_START;
			
			// Immediately try to connect directly to the AE
			// Note that these are just opportunistic connections,
			// and will only succeed if the AE has a direct internet connection, or a port mapping.
			
			[remote_externalIP release];
			
			remote_externalIP = [[message ip4] copy];
			remote_serverPort = [message serverPort];
			remote_predictedPort = [message predictedPort];
			
			if(remote_serverPort > 0)
			{
				asock = [[AsyncSocket alloc] initWithDelegate:self];
				[asock connectToHost:remote_externalIP onPort:remote_serverPort error:nil];
				
				DDLogVerbose(@"STUNTSocket: attempting connection to %@:%i",
							 remote_externalIP, remote_serverPort);
			}
			
			if(remote_predictedPort > 0)
			{
				bsock = [[AsyncSocket alloc] initWithDelegate:self];
				[bsock connectToHost:remote_externalIP onPort:remote_predictedPort error:nil];
				
				DDLogVerbose(@"STUNTSocket: attempting connection to %@:%i",
							 remote_externalIP, remote_predictedPort);
			}
			
			// Fork off background thread to perform port prediction
			[NSThread detachNewThreadSelector:@selector(portPredictionThread) toTarget:self withObject:nil];
		}
		else
		{
			// We received an error message
			if([message errorMessage])
			{
				[logger setFailureReason:[NSString stringWithFormat:@"RCV: %@", [message errorMessage]]];
			}
			else
			{
				NSString *format = @"Expecting invite message, received '%@' message";
				NSString *reason = [NSString stringWithFormat:format, [message type]];
				[logger setFailureReason:reason]; 
			}
			[self fail];
		}
	}
	else
	{
		DDLogWarn(@"STUNTSocket: Received message(%@) without matching state(%@)",
				  [message type], StringFromState(state));
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Port Mapping
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)portMappingDidChange:(NSNotification *)notification
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	if([portMapping mappingStatus] == TCMPortMappingStatusMapped)
	{
		DDLogInfo(@"STUNTSocket: Mapped Server Port: L(%i) <-> E(%i)",
				  [portMapping localPort], [portMapping externalPort]);
		
		[logger setPortMappingAvailable:YES];
		[logger setPortMappingProtocol:[[TCMPortMapper sharedInstance] mappingProtocol]];
		
		// The mapped port may be different than the port we requested.
		// Store the mapped port - it will be sent to the remote user now instead of the server port.
		local_mappedServerPort = [portMapping externalPort];
	}
	else
	{
		TCMPortMapping *serverPortMapping = [[NSApp delegate] serverPortMapping];
		
		if([serverPortMapping mappingStatus] == TCMPortMappingStatusMapped)
		{
			[logger setPortMappingAvailable:YES];
			[logger setPortMappingProtocol:[[TCMPortMapper sharedInstance] mappingProtocol]];
			
			// The external port is almost guaranteed to be the server port, but we'll save it just in case.
			// Note that we're NOT setting the local_mappedServerPort here.
			// We use local_mappedServerPort to determine if we created the mapping or if the AppDelegate did.
			local_serverPort = [serverPortMapping externalPort];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Port Prediction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Background thread to handle port prediction.
 * This requires the synchronous fetching of multiple URL's in succession from the same local port number
**/
- (void)portPredictionThread
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	DDLogVerbose(@"Port Prediction started...");
	
	// Generate a random port number (1024 - 65535) to use
	local_internalPort = [STUNTUtilities randomPortNumber];
	
	DDLogVerbose(@"local port: %i", local_internalPort);
	
	// Setup port prediction logger
	STUNTPortPredictionLogger *ppLogger = [[STUNTPortPredictionLogger alloc] initWithLocalPort:local_internalPort];
	[ppLogger autorelease];
	
	UInt16 externalPort1 = 0;
	UInt16 externalPort2 = 0;
	
	// Now connect to the first URL, and obtain external IP and port number
	NSData *data1 = [STUNTUtilities downloadURL:[NSURL URLWithString:URL_IP_PORT_1]
									onLocalPort:local_internalPort
										timeout:3.0];
	
	NSString *result1 = [[[NSString alloc] initWithData:data1 encoding:NSUTF8StringEncoding] autorelease];
	
	NSArray *array1 = [result1 componentsSeparatedByString:@":"];
	if([array1 count] == 2)
	{
		NSString *externalIP1 = [array1 objectAtIndex:0];
		externalPort1 = [[array1 objectAtIndex:1] intValue];
		
		DDLogVerbose(@"result1: %@:%i", externalIP1, externalPort1);
		
		if(local_internalPort == externalPort1)
		{
			// The localPort and external port number actually match.
			// This either means we have a direct connection to the Internet, or
			// we're behind a router that uses port preservation.
			// In either case, an outgoing packet on port X should arrive at it's destination from port X
			
			// However, some routers have trouble reusing the exact same port, from the same computer,
			// to create a new socket to a different address.  The router seems to still have state setup for
			// the last connection (in time_wait mode maybe), and then assigns port numbers in NB:connection_1 mode.
			// To avoid this problem, we'll simply switch to a new port.
			// Note that we switch to a close port so we're most likely to continue experiencing port preservation.
			
			[local_externalIP release];
			local_externalIP = [externalIP1 copy];
			
			local_internalPort = local_internalPort + 1;
			local_predictedPort = local_internalPort;
			
			DDLogVerbose(@"Assuming direct connection or router using port preservation...");
		}
		else
		{
			// Now connect to the second URL, and obtain external IP and port number
			NSData *data2 = [STUNTUtilities downloadURL:[NSURL URLWithString:URL_IP_PORT_2]
											onLocalPort:local_internalPort
												timeout:3.0];
			
			NSString *result2 = [[[NSString alloc] initWithData:data2 encoding:NSUTF8StringEncoding] autorelease];
			
			NSArray *array2 = [result2 componentsSeparatedByString:@":"];
			if([array2 count] == 2)
			{
				NSString *externalIP2 = [array2 objectAtIndex:0];
				externalPort2 = [[array2 objectAtIndex:1] intValue];
				
				DDLogVerbose(@"result2: %@:%i", externalIP2, externalPort2);
				
				[local_externalIP release];
				local_externalIP = [externalIP1 copy];
				
				local_predictedPort = externalPort2 + (externalPort2 - externalPort1);
			}
			else
			{
				DDLogVerbose(@"result2: [failure]");
				
				// The second lookup failed, but we still have the result of the first lookup
				// We'll assume NB:independent mode, as it's statistically the most likely
				[local_externalIP release];
				local_externalIP = [externalIP1 copy];
				
				local_predictedPort = local_internalPort;
			}
		}
	}
	else
	{
		DDLogVerbose(@"result1: [failure]");
		
		// The first lookup failed for some reason
		// We'll try to make an educated guess from the second lookup
		
		// Just in case it was the choice of port number, we'll pick a new one
		local_internalPort = [STUNTUtilities randomPortNumber];
		
		NSData *data2 = [STUNTUtilities downloadURL:[NSURL URLWithString:URL_IP_PORT_2]
										onLocalPort:local_internalPort
											timeout:3.0];
		
		NSString *result2 = [[[NSString alloc] initWithData:data2 encoding:NSUTF8StringEncoding] autorelease];
		
		NSArray *array2 = [result2 componentsSeparatedByString:@":"];
		if([array2 count] == 2)
		{
			NSString *externalIP2 = [array2 objectAtIndex:0];
			externalPort2 = [[array2 objectAtIndex:1] intValue];
			
			DDLogVerbose(@"result2: %@:%i", externalIP2, externalPort2);
			
			if(local_internalPort == externalPort2)
			{
				// The localPort and external port number actually match.
				// This either means we have a direct connection to the Internet, or
				// we're behind a router that uses port preservation.
				// In either case, an outgoing packet on port X should arrive at it's destination from port X
				
				// However, some routers have trouble reusing the exact same port, from the same computer,
				// to create a new socket to a different address.  The router seems to still have state setup for
				// the last connection (in time_wait mode maybe), and then assigns port numbers in NB:connection_1 mode.
				// To avoid this problem, we'll simply switch to a new port.
				// Note that we switch to a close port so we're most likely to continue experiencing port preservation.
				
				[local_externalIP release];
				local_externalIP = [externalIP2 copy];
				
				local_internalPort = local_internalPort + 1;
				local_predictedPort = local_internalPort;
				
				DDLogVerbose(@"Assuming direct connection or router using port preservation...");
			}
			else
			{
				// We'll assume NB:independent mode, as it's statistically the most likely
				[local_externalIP release];
				local_externalIP = [externalIP2 copy];
				
				local_predictedPort = local_internalPort;
			}
		}
		else
		{
			DDLogVerbose(@"result2: [failure]");
			
			// Well neither lookup worked... We're screwed.
			[local_externalIP release];
			local_externalIP = nil;
			
			local_predictedPort = 0;
		}
	}
	
	[ppLogger setReportedPort1:externalPort1];
	[ppLogger setReportedPort2:externalPort2];
	[ppLogger setPredictedPort1:local_predictedPort];
	
	[self performSelectorOnMainThread:@selector(portPredictionFinished:) withObject:ppLogger waitUntilDone:YES];
		
	[pool release];
}

/**
 * This method is called after the port prediction thread is finished.
 * It is executed on the primary thread.
**/
- (void)portPredictionFinished:(STUNTPortPredictionLogger *)ppLogger
{
	DDLogVerbose(@"STUNTSocket: portPredictionFinished:");
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(state == STATE_AE_START || state == STATE_PE_SWAP_SENT)
	{
		[logger addPortPredictionLogger:ppLogger];
		
		if(local_externalIP == nil || local_internalPort == 0 || local_predictedPort == 0)
		{
			DDLogError(@"STUNTSocket: Unable to perform port prediction");
			
			// We were unable to fetch our external IP address
			// But obviously, we only send an error message if we've already started the STUNT procedure
			if(state == STATE_PE_SWAP_SENT)
			{
				STUNTMessage *message = [STUNTMessage messageWithType:@"error" to:jid uuid:uuid];
				[message setErrorMessage:@"Unable to perform port prediction"];
				
				[self sendStuntMessage:message];
			}
			
			[logger setFailureReason:@"Unable to perform port prediction"];
			[self fail];
		}
		else
		{
			// Port prediction is complete
			// Time to send our INVITE message to the server
			
			STUNTMessage *message = [STUNTMessage messageWithType:@"invite" to:jid uuid:uuid];
			[message setIP4:local_externalIP];
			[message setPredictedPort:local_predictedPort];
			
			if(!isClient)
			{
				// We also include the port the server is running on.
				// This allows connections to succeed when using port forwarding or port mapping in the router,
				// by allowing the remote client to connect directly to our server.
				
				if(local_mappedServerPort > 0)
					[message setServerPort:local_mappedServerPort];
				else
					[message setServerPort:local_serverPort];
			}
			else if([remote_stuntVersion floatValue] >= 1.1)
			{
				// Although we're the client, and we're trying to create an outgoing TCP connection,
				// we're going to tell the remote client to attempt to connect directly to our server.
				// The reason this is OK is because the remote client will perform validation if the
				// connection succeeds. This validation allows us to steal the socket from the server.
				// This allows connections to succeed when using port forwarding or port mapping in the router.
				
				if(local_mappedServerPort > 0)
					[message setServerPort:local_mappedServerPort];
				else
					[message setServerPort:local_serverPort];
			}
			
			[self sendStuntMessage:message];
			
			// Update state
			state = STATE_AE_INVITE_SENT;
						
			// Now we need to start listening for a connection
			// The only time this connection will succeed is when we have a direct internet connection
			psock = [[AsyncSocket alloc] initWithDelegate:self];
			[psock acceptOnPort:local_internalPort error:nil];
			
			DDLogVerbose(@"STUNTSocket: accepting connections on port: %i", local_internalPort);
		}
	}
	else if(state == STATE_PE_START)
	{
		[logger addPortPredictionLogger:ppLogger];
		
		if(local_externalIP == nil || local_internalPort == 0 || local_predictedPort == 0)
		{
			DDLogError(@"STUNTSocket: Unable to perform port prediction");
			
			// We were unable to fetch our external IP address
			// Send an error message response
			
			STUNTMessage *message = [STUNTMessage messageWithType:@"error" to:jid uuid:uuid];
			[message setErrorMessage:@"Unable to perform port prediction"];
			
			[self sendStuntMessage:message];
			
			[logger setFailureReason:@"Unable to perform port prediction"];
			[self fail];
		}
		else
		{
			// We properly fetched our external IP address
			// Stick the address and port in a message, and reply to the request message
			
			STUNTMessage *message = [STUNTMessage messageWithType:@"accept" to:jid uuid:uuid];
			[message setIP4:local_externalIP];
			[message setPredictedPort:local_predictedPort];
			
			[self sendStuntMessage:message];
			
			// Update state
			state = STATE_PE_ACCEPT_SENT;
						
			// Now we need to start listening for a connection
			// The only time this connection will succeed is when we have a direct internet connection
			psock = [[AsyncSocket alloc] initWithDelegate:self];
			[psock acceptOnPort:local_internalPort error:nil];
			
			DDLogVerbose(@"STUNTSocket: accepting connections on port: %i", local_internalPort);
		}
	}
	else
	{
		DDLogVerbose(@"STUNTSocket: Port prediction results ignored. It appears we're done.");
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncSocket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	if(sock == asock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:asock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==asock"];
	}
	if(sock == bsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:bsock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==bsock"];
	}
	if(sock == psock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:psock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==psock"];
	}
	if(sock == qsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:qsock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==qsock"];
	}
	if(sock == rsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:rsock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==rsock"];
	}
	if(sock == fsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:fsock willDisconnectWithError:%@", err);
		[logger addTraceMessage:@"sock==fsock"];
	}
}

- (BOOL)onSocketWillConnect:(AsyncSocket *)sock
{
	if(state == STATE_AE_ACCEPT_RECEIVED || state == STATE_PE_CALLBACK_RECEIVED)
	{
		[logger addTraceMethod:NSStringFromSelector(_cmd)];
		[logger addTraceMessage:StringFromState(state)];
		
		// Case STATE_AE_ACCEPT_RECEIVED:
		// We have properly exchanged port prediction information with the passive endpoint.
		// Now we're going to attempt to connect to the passive endpoint.
		// This connection will only succeed if the PE has a direct connection to the Internet, or they're behind
		// a router with an odd combination such as port preservation along with EF:Independent.
		// The primary purpose of this connection attempt it to "punch a hole" in our NAT.
		// That is, our NAT will see an outgoing SYN and will hopefully allow incoming traffic afterwards.
		// It will only do so, however, if the local port matches, along with the remote address and remote port.
		// Thus, we need to make sure to send the SYN from the local port we specified earlier.
		
		// Case STATE_PE_CALLBACK_RECEIVED:
		// The active endpoint attempted to connect to us but was unsuccessfull.  This was no surprise.
		// However, the AE has now hopefully punched a hole in it's NAT, and we may be able to connect.
		// In order for this to work, we have to make sure to connect from the local port we specified earlier.
		
		CFSocketRef theSocket = [sock getCFSocket];
				
		if(theSocket)
		{
			CFSocketNativeHandle theNativeSocket = CFSocketGetNative(theSocket);
			
			if(theNativeSocket == 0)
			{
				DDLogError(@"STUNTSocket: Error - Could not get native socket handle from AsyncSocket");
				return NO;
			}
			
			int reuseOn = 1;
			setsockopt(theNativeSocket, SOL_SOCKET, SO_REUSEADDR, &reuseOn, sizeof(reuseOn));
			
			DDLogVerbose(@"STUNTSocket: Binding socket to local port...");
			
			struct sockaddr_in localAddress;
			localAddress.sin_len         = sizeof(struct sockaddr_in);
			localAddress.sin_family      = AF_INET;
			localAddress.sin_port        = htons(local_internalPort);
			localAddress.sin_addr.s_addr = htonl(INADDR_ANY);
			memset(localAddress.sin_zero, 0, sizeof(localAddress.sin_zero));
			
			int result = bind(theNativeSocket, (struct sockaddr *)&localAddress, sizeof(localAddress));
			if(result == -1)
			{
				DDLogError(@"STUNTSocket: Error - Could not bind socket: %d: %s", errno, strerror(errno));
				[logger addTraceMessage:@"Error - Cound not bind socket: %d: %s", errno, strerror(errno)];
				return NO;
			}
		}
		else
		{
			DDLogError(@"STUNTSocket: Error - Could not get CFSocketRef from AsyncSocket");
			[logger addTraceMessage:@"Error - Could not get CFSocketRef from AsyncSocket"];
			return NO;
		}
	}
	return YES;
}

/**
 * Called when a socket accepts a connection.  Another socket is spawned to handle it. The new socket will have
 * the same delegate and will call "onSocket:didConnectToHost:port:".
**/
- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
{
	DDLogVerbose(@"STUNTSocket: onSocket:%p didAcceptNewSocket:%p", sock, newSocket);
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(state == STATE_AE_INVITE_SENT   ||
	   state == STATE_PE_ACCEPT_SENT   || 
	   state == STATE_AE_CALLBACK_SENT ||
	   state == STATE_AE_I_VALIDATION   )
	{
		// Case STATE_AE_INVITE_SENT:
		// Case STATE_PE_ACCEPT_SENT:
		//   We accepted a direct connection from the other computer.
		//   This probably means we have a direct internet connection, or
		//   we're behind a router using EF:Independent (independent endpoint filtering).
		// 
		// Case STATE_AE_CALLBACK_SENT:
		//   We accepted a connection after punching a hole in the router.
		// 
		// Case STATE_AE_I_VALIDATION:
		//   We have already accepted an incoming connection via the server.
		//   We are now also accepting an incoming connection from psock.
		//   Both connections will be accepted, and validation will be performed on each.
		//   This way, if either connection fails validation, we've got a backup.
		
		// Store reference to final connected socket
		// This will be the AsyncSocket reference we return to caller in the connectedSocket method
		// We also need to be sure to retain the socket, since it's a new socket
		qsock = [newSocket retain];
		
		// And we can stop accepting connections now too
		[psock setDelegate:nil];
		[psock disconnect];
		[psock release];
		psock = nil;
		
		// Record what state we were in upon success
		[logger setSuccessState:state];
		
		// Update state
		// This simple act should prevent any further action from being taken in this STUNTSocket object,
		// since every action is dictated based on the current state
		if([self isActiveEndpoint])
			state = STATE_AE_I_VALIDATION;
		else
			state = STATE_PE_I_VALIDATION;
		
		// We will wait until the onSocket:didConnectToHost:port: method is called to notify those concerned.
		// This method is guaranteed to be called shortly after the current method completes.
		// The purpose of waiting is that the socket will always be in the same state upon notification,
		// regardless of whether we accepted the connection or initiated the connection.
	}
}

/**
 * Called when a socket connects and is ready for reading and writing. "host" will be an IP address, not a DNS name.
**/
- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(sock == asock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:asock didConnectToHost:%@ port:%hu", host, port);
		[logger addTraceMessage:@"sock==asock"];
	}
	if(sock == bsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:bsock didConnectToHost:%@ port:%hu", host, port);
		[logger addTraceMessage:@"sock==bsock"];
	}
	if(sock == qsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:qsock didConnectToHost:%@ port:%hu", host, port);
		[logger addTraceMessage:@"sock==qsock"];
	}
	
	if(state == STATE_PE_START             ||
	   state == STATE_PE_ACCEPT_SENT       ||
	   state == STATE_AE_ACCEPT_RECEIVED   ||
	   state == STATE_PE_CALLBACK_RECEIVED ||
	   state == STATE_PE_O_VALIDATION       )
	{
		// Case STATE_PE_START:
		// Case STATE_PE_ACCEPT_SENT:
		//   We were able to connect directly to the other host.
		//   This means they probably had a direct internet connection, or a port mapping.
		//   sock may be asock or bsock.
		// 
		// Case STATE_AE_ACCEPT_RECEIVED:
		//   We were able to connect directly to the other host
		//   This means they probably had a direct internet connection, or a port mapping.
		//   sock is bsock.
		// 
		// Case STATE_PE_CALLBACK_RECEIVED:
		//   We were able to negotiate a connection by punching a hold in the router.
		//   If the other host was behind a router with EF:Independent or EF:Address,
		//   then they got their port prediction correct.
		//   If the other host was behind a router with EF:AddressAndPort,
		//   then we both got our port prediction correct.
		//   sock is bsock.
		// 
		// Case STATE_PE_O_VALIDATION:
		//   We have already connected to the other host.
		//   We are now connecting a second time.
		//   This might happen when both asock and bsock successfully make a connection.
		//   Validation will be performed on each.
		//   This way, if either connection fails validation, we've got a backup.
		//   sock may be asock or bscok.
		
		// Record what state we were in upon success
		[logger setSuccessState:state];
		
		// Update state
		// This simple act should prevent any further action from being taken in this STUNTSocket object,
		// since every action is dictated based on the current state
		if([self isActiveEndpoint])
			state = STATE_AE_O_VALIDATION;
		else
			state = STATE_PE_O_VALIDATION;
		
		if(sock == asock)
			[self maybeValidateC2SConnection:sock];
		else
			[self maybeValidateP2PConnection:sock];
	}
	else if(state == STATE_AE_I_VALIDATION || state == STATE_PE_I_VALIDATION)
	{
		// We accepted a connection from the other endpoint,
		// and we've been notified that the connection is now fully connected and ready for use.
		
		// There's no reason to store a reference to the socket
		// as we already took care of that in the onSocket:didAcceptNewSocket: method.
		// In other words, the qsock variable already points to it, and has already retained it.
		
		[self maybeValidateP2PConnection:sock];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection Timeouts
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)doCallbackTimeout:(NSTimer *)aTimer
{
	if(state == STATE_AE_ACCEPT_RECEIVED)
	{
		DDLogVerbose(@"STUNTSocket: doCallbackTimeout:");
		[logger addTraceMethod:NSStringFromSelector(_cmd)];
		
		// Close the socket we were trying to connect with
		[bsock setDelegate:nil];
		[bsock disconnect];
		[bsock release];
		bsock = nil;
		
		// Send callback message
		
		STUNTMessage *message = [STUNTMessage messageWithType:@"callback" to:jid uuid:uuid];
		
		[self sendStuntMessage:message];
		
		// Update state
		state = STATE_AE_CALLBACK_SENT;
		
		// Now we need to start listening for a connection
		// This should succeed if port prediction was correct on both computers
		psock = [[AsyncSocket alloc] initWithDelegate:self];
		[psock acceptOnPort:local_internalPort error:nil];
		
		DDLogVerbose(@"STUNTSocket: acepting connections on port %i", local_internalPort);
	}
}

- (void)doSwapTimeout:(NSTimer *)aTimer
{
	if(state == STATE_PE_CALLBACK_RECEIVED)
	{
		DDLogVerbose(@"STUNTSocket: doSwapTimeout:");
		[logger addTraceMethod:NSStringFromSelector(_cmd)];
		
		// Close the socket we were trying to connect with
		[bsock setDelegate:nil];
		[bsock disconnect];
		[bsock release];
		bsock = nil;
		
		// Check attempt count and decide whether or not to continue
		if((isClient) && (++attemptCount > MAX_ATTEMPTS))
		{
			// Send error message
			STUNTMessage *message = [STUNTMessage messageWithType:@"error" to:jid uuid:uuid];
			[message setErrorMessage:@"Exceeded max number of attempts"];
			
			[self sendStuntMessage:message];
			
			[logger setFailureReason:@"Exceeded max number of attempts"];
			[self fail];
		}
		else
		{
			// Send swap message
			STUNTMessage *message = [STUNTMessage messageWithType:@"swap" to:jid uuid:uuid];
			
			[self sendStuntMessage:message];
			
			// Update state
			state = STATE_PE_SWAP_SENT;
			
			// Fork off background thread to perform port prediction
			[NSThread detachNewThreadSelector:@selector(portPredictionThread) toTarget:self withObject:nil];
		}
	}
}

- (void)doTotalTimeout:(NSTimer *)aTimer
{
	if(state != STATE_AE_DONE && state != STATE_AE_FAILURE &&
	   state != STATE_PE_DONE && state != STATE_PE_FAILURE)
	{
		DDLogVerbose(@"STUNTSocket: doTotalTimeout:");
		[logger addTraceMethod:NSStringFromSelector(_cmd)];
		[logger addTraceMessage:StringFromState(state)];
		
		// A timeout occured to cancel the entire STUNT procedure
		// This probably means the other endpoint crashed, or a network error occurred
		// In either case, we can consider this a failure, and recycle the memory associated with this object
		
		[logger setFailureReason:@"Timed out"];
		[self fail];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection Validation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)markReadValidationCompleteForSocket:(AsyncSocket *)sock
{
	DDLogVerbose(@"STUNTSocket: markReadValidationCompleteForSocket:%p", sock);
	
	[sock setUserData:([sock userData] | kReadValidationComplete)];
}

- (void)markWriteValidationCompleteForSocket:(AsyncSocket *)sock
{
	DDLogVerbose(@"STUNTSocket: markWriteValidationCompleteForSocket:%p", sock);
	
	[sock setUserData:([sock userData] | kWriteValidationComplete)];
}

- (BOOL)isValidationCompleteForSocket:(AsyncSocket *)sock
{
	long sockUserData = [sock userData];
	
	return ((sockUserData & kReadValidationComplete) && (sockUserData & kWriteValidationComplete));
}

- (NSString *)hexHash:(NSString *)hashMe
{
	SSCrypto *crypto = [[SSCrypto alloc] init];
	
	[crypto setClearTextWithString:hashMe];
	NSString *result = [[crypto digest:@"MD5"] hexval];
	
	[crypto release];
	
	return [result uppercaseString];
}

/**
 * Starting with version 1.1, we verify the connection.
 * This is done to ensure that we connected to the right computer.
 * 
 * We do this by having each side send a special token, followed by \r\n.
 * The special token is an MD5 hash of the bare JID of the sender and the UUID.
**/
- (void)maybeValidateP2PConnection:(AsyncSocket *)sock
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Note: sock may be bsock or qsock
	
	if([remote_stuntVersion floatValue] >= 1.1)
	{
		[self startP2PValidation:sock];
	}
	else
	{
		if(remote_stuntVersion == nil)
		{
			DDLogVerbose(@"STUNTSocket: Unsure of remote stunt version...");
			[logger addTraceMessage:@"Unsure of remote stunt version..."];
			
			// Corner case:
			// We accepted a direct TCP connection prior to receiving any xmpp stunt messages from the remote user.
			// 
			// This may happen if we have a direct internet connection,
			// and we accepted a connection in state STATE_AE_INVITE_SENT.
			// We can't start validation, because the remote user might not support it.
			// We can't skip validation, because the remote user might require it.
			// Instead what we'll do is wait a few seconds to see if the user sends us anything.
			// If any bytes become available on the wire, then it must be the validation information.
			// 
			// Note: Validation is expected to be the most common case.
			
			[NSThread detachNewThreadSelector:@selector(checkForValidationThread:) toTarget:self withObject:sock];
		}
		else
		{
			// Remote user doesn't support validation
			[self skipP2PValidation:sock];
		}
	}
}

/**
 * This thread is spawned when we're unsure what stunt version the remote user is running,
 * and thus we're unsure if they require connection validation or not.
 * So what we do is wait a few seconds to see if validation info appears on the wire.
**/
- (void)checkForValidationThread:(AsyncSocket *)sock
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	CFReadStreamRef readStream = [sock getCFReadStream];
	
	bool foundValidation = NO;
	
	// We wait up to 2 seconds waiting to see if any validation info appears on the wire
	
	int i;
	for(i = 0; i < 20 && !foundValidation; i++)
	{
		// Sleep for 100 milliseconds
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	
		// Check for data on the socket
		if(CFReadStreamHasBytesAvailable(readStream))
		{
			// There's data available on the socket - it must be validation info
			[self performSelectorOnMainThread:@selector(startP2PValidation:) withObject:sock waitUntilDone:NO];
			
			foundValidation = YES;
		}
	}
	
	if(!foundValidation)
	{
		// It appears the remote user doesn't support validation
		[self performSelectorOnMainThread:@selector(skipP2PValidation:) withObject:sock waitUntilDone:NO];
	}
	
	[pool release];
}

/**
 * Starts the P2P validation process.
 * This method is called after it has been determined that the remote host supports validation.
**/
- (void)startP2PValidation:(AsyncSocket *)sock
{
	DDLogVerbose(@"STUNTSocket: Validating P2P connection...");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Note: sock may be bsock or qsock
	
	// Send our validation message to the remote client.
	// It should be of the form:
	// Hex(MD5(myJid.Bare + uuid)) + "\r\n"
	
	NSString *bareJID = [[[MojoXMPPClient sharedInstance] myJID] bare];
	NSString *hashMe = [NSString stringWithFormat:@"%@%@", bareJID, uuid];
	
	NSString *sendMe = [NSString stringWithFormat:@"%@\r\n", [self hexHash:hashMe]];
	
	[sock writeData:[sendMe dataUsingEncoding:NSUTF8StringEncoding] withTimeout:5.0 tag:0];
	
	// Start reading the validation message from the remote client
	
	[sock readDataToData:[AsyncSocket CRLFData] withTimeout:5.0 tag:0];
}

/**
 * Skips the P2P validation process.
 * This method is called after it has been determined that the remote host does NOT support validation.
**/
- (void)skipP2PValidation:(AsyncSocket *)sock
{
	DDLogWarn(@"STUNTSocket: remote user doesn't support validation...");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger setValidation:STUNT_VALIDATION_NONE];
	
	[self succeed:sock];
}

/**
 * Starting with version 1.1, we verify the connection.
 * This is done to ensure that we connected to the right computer.
 *
 * We do this by sending a special HTTP STUNT request.
 * The remote HTTP server will then connect our TCP socket to the proper stunt socket object.
 * It will then send us the usual validation token.
**/
- (void)maybeValidateC2SConnection:(AsyncSocket *)sock
{
	DDLogVerbose(@"STUNTSocket: maybeValidateC2SConnection:");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger setConnectionViaServer:YES];
	
	// Note: sock is asock
	
	if([remote_stuntVersion floatValue] >= 1.1)
	{
		DDLogVerbose(@"STUNTSocket: Validating C2S connection...");
		[logger addTraceMessage:@"Starting validation"];
		
		// Send our validation message to the remote client.
		// It should be an HTTP Header of the form:
		// STUNT / HTTP/1.1
		// Validation: Hex(MD5(myJID.Bare + uuid))
		
		NSString *bareJID = [[[MojoXMPPClient sharedInstance] myJID] bare];
		NSString *hashMe = [NSString stringWithFormat:@"%@%@", bareJID, uuid];
		
		NSString *line1 = @"STUNT / HTTP/1.1";
		NSString *line2 = [NSString stringWithFormat:@"Validation: %@", [self hexHash:hashMe]];
		
		NSString *header = [NSString stringWithFormat:@"%@\r\n%@\r\n\r\n", line1, line2];
		
		[sock writeData:[header dataUsingEncoding:NSUTF8StringEncoding] withTimeout:5 tag:0];
		
		[sock readDataToData:[AsyncSocket CRLFData] withTimeout:5 tag:0];
	}
	else
	{
		DDLogWarn(@"STUNTSocket: remote user doesn't support validation...");
		
		[logger addTraceMessage:@"Skipping validation"];
		[logger setValidation:STUNT_VALIDATION_NONE];
		[self succeed:sock];
	}
}

/**
 * This method may be called whenever our Mojo HTTP server receives a STUNT validation request.
 * This means another client was able to directly connect to our HTTP server,
 * and is looking to validate the connection by making sure they connected to us, and not an imposter.
 *
 * We need to determine, based on the sent hash, if this validation message if for us, or another STUNTSocket.
 * If the message is for us, we are to take ownership of the socket and return YES.
**/
- (BOOL)handleStuntValidation:(NSString *)hash fromSocket:(AsyncSocket *)sock
{
	if(state == STATE_AE_DONE || state == STATE_AE_FAILURE || state == STATE_PE_DONE || state == STATE_PE_FAILURE)
	{
		DDLogWarn(@"STUNTSocket: handleStuntValidation called while state is %i", state);
		return NO;
	}
	
	// Check the hash, and make sure it's correct.
	// It should be:
	// Hex(MD5(sender.jid.bare + uuid))
	
	NSString *hashMe = [NSString stringWithFormat:@"%@%@", [jid bare], uuid];
		
	NSString *compareMe = [self hexHash:hashMe];
		
	if([compareMe isEqualToString:hash])
	{
		DDLogVerbose(@"STUNTSocket: handleStuntValidation: Hash matches!");
		
		[self finishC2SValidation:sock];
		
		return YES;
	}
	else
	{
		return NO;
	}
}

/**
 * The remote client connected to our server, and sent a proper validation request.
 * The only thing left to do is send our own validation.
**/
- (void)finishC2SValidation:(AsyncSocket *)sock
{
	DDLogVerbose(@"STUNTSocket: FinishC2SValidation");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// Update logger information
	[logger setSuccessState:state];
	[logger setConnectionViaServer:YES];
	
	// Take ownership of the socket.
	// Remember, the socket is coming from an HTTPConnection.
	rsock = [sock retain];
	[rsock setUserData:0];
	[rsock setDelegate:self];
	
	// We've already received and confirmed validation from the remote client
	[self markReadValidationCompleteForSocket:rsock];
	
	// Update state
	state = STATE_AE_I_VALIDATION;
	
	// Send our validation message to the remote client.
	// It should be of the form:
	// Hex(MD5(myJID.Bare + uuid)) + "\r\n"
	
	NSString *bareJID = [[[MojoXMPPClient sharedInstance] myJID] bare];
	NSString *hashMe = [NSString stringWithFormat:@"%@%@", bareJID, uuid];
	
	NSString *sendMe = [NSString stringWithFormat:@"%@\r\n", [self hexHash:hashMe]];
	
	[rsock writeData:[sendMe dataUsingEncoding:NSUTF8StringEncoding] withTimeout:5 tag:0];
}

- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(sock == asock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:asock didWriteDataWithTag:");
		[logger addTraceMessage:@"sock==asock"];
	}
	if(sock == bsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:bsock didWriteDataWithTag:");
		[logger addTraceMessage:@"sock==bsock"];
	}
	if(sock == qsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:qsock didWriteDataWithTag:");
		[logger addTraceMessage:@"sock==qsock"];
	}
	if(sock == rsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:rsock didWriteDataWithTag:");
		[logger addTraceMessage:@"sock==rsock"];
	}
	
	// Check state
	// If we have multiple connections, we may already be done
	
	if(state == STATE_AE_I_VALIDATION ||
	   state == STATE_AE_O_VALIDATION ||
	   state == STATE_PE_I_VALIDATION ||
	   state == STATE_PE_O_VALIDATION  )
	{
		// The socket finished sending its validation message
		[self markWriteValidationCompleteForSocket:sock];
		
		// Wait for all IO to complete before we hand the socket over to others
		if([self isValidationCompleteForSocket:sock])
		{
			[logger setValidation:STUNT_VALIDATION_SUCCESS];
			[self succeed:sock];
		}
	}
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData*)data withTag:(long)tag
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(sock == asock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:asock didReadData:withTag:");
		[logger addTraceMessage:@"sock==asock"];
	}
	if(sock == bsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:bsock didReadData:withTag:");
		[logger addTraceMessage:@"sock==bsock"];
	}
	if(sock == qsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocket:qsock didReadData:withTag:");
		[logger addTraceMessage:@"sock==qsock"];
	}
	
	// Check state
	// If we have multiple connections, we may already be done
	
	if(state == STATE_AE_I_VALIDATION ||
	   state == STATE_AE_O_VALIDATION ||
	   state == STATE_PE_I_VALIDATION ||
	   state == STATE_PE_O_VALIDATION  )
	{
		// The socket is finished reading its validation message.
		// Check the read data, and make sure it's correct.
		// It should be:
		// Hex(MD5(sender.jid.bare + uuid)) + "\r\n"
		
		NSString *hashMe = [NSString stringWithFormat:@"%@%@", [jid bare], uuid];
		
		NSString *compareMe = [NSString stringWithFormat:@"%@\r\n", [self hexHash:hashMe]];
		
		NSString *dataStr = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		
		if([compareMe isEqualToString:dataStr])
		{
			DDLogVerbose(@"STUNTSocket: Connection validated");
			
			// The received validation message is confirmed
			[self markReadValidationCompleteForSocket:sock];
			
			// Wait for all IO to complete before we hand the socket over to others
			if([self isValidationCompleteForSocket:sock])
			{
				[logger setValidation:STUNT_VALIDATION_SUCCESS];
				[self succeed:sock];
			}
		}
		else
		{
			DDLogWarn(@"STUNTSocket: Connection failed validation!");
			[logger addTraceMessage:@"Validation failed"];
			
			// It would appear that we connected to the wrong computer.
			// Close the socket to free resources, and allow the disconnect delegate to handle the failure.
			[sock disconnect];
		}
	}
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(sock == asock)
	{
		DDLogVerbose(@"STUNTSocket: onSocketDidDisconnect:asock");
		[logger addTraceMessage:@"sock==asock"];
	}
	if(sock == bsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocketDidDisconnect:bsock");
		[logger addTraceMessage:@"sock==bsock"];
	}
	if(sock == qsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocketDidDisconnect:qsock");
		[logger addTraceMessage:@"sock==qsock"];
	}
	if(sock == rsock)
	{
		DDLogVerbose(@"STUNTSocket: onSocketDidDisconnect:rsock");
		[logger addTraceMessage:@"sock==rsock"];
	}
	
	// If we were in the middle of validation, this could mean a failure.
	// But we have potential backup connections, so we may be able to recover from a single validation failure.
	// 
	// Both asock and bsock may have connected.
	// If so, we don't fail until they both disconnect.
	// 
	// Both qsock and rsock may have incoming connections (qsock from psock, and rsock from the server).
	// If so, we don't fail until they both disconnect.
	
	if(state == STATE_AE_I_VALIDATION ||
	   state == STATE_AE_O_VALIDATION ||
	   state == STATE_PE_I_VALIDATION ||
	   state == STATE_PE_O_VALIDATION  )
	{
		BOOL failed = NO;
		
		if(sock == asock)
			failed = ![bsock isConnected];
		
		if(sock == bsock)
			failed = ![asock isConnected];
		
		if(sock == qsock)
			failed = ![rsock isConnected];
		
		if(sock == rsock)
			failed = ![qsock isConnected];
		
		if(failed)
		{
			[logger setValidation:STUNT_VALIDATION_FAILURE];
			[logger setFailureReason:@"Validation failure"];
			[self fail];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Finish and Cleanup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)succeed:(AsyncSocket *)sock
{
	DDLogInfo(@"STUNTSocket: SUCCESS");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// Record finish time
	finishTime = [[NSDate alloc] init];
	
	// Store reference to successful socket
	fsock = [sock retain];
	
	// Update state
	if([self isActiveEndpoint])
		state = STATE_AE_DONE;
	else
		state = STATE_PE_DONE;
	
	if([delegate respondsToSelector:@selector(stuntSocket:didSucceed:)])
	{
		[delegate stuntSocket:self didSucceed:fsock];
	}
	
	[logger setSuccess:YES];
	[logger setSuccessCycle:attemptCount];
	[logger setDuration:[finishTime timeIntervalSinceDate:startTime]];
	[STUNTUtilities sendStuntFeedback:logger];
	
	[self cleanup];
}

- (void)fail
{
	DDLogInfo(@"STUNTSocket: FAILURE");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// Record finish time
	finishTime = [[NSDate alloc] init];
	
	// Update state
	if([self isActiveEndpoint])
		state = STATE_AE_FAILURE;
	else
		state = STATE_PE_FAILURE;
	
	if([delegate respondsToSelector:@selector(stuntSocketDidFail:)])
	{
		[delegate stuntSocketDidFail:self];
	}
	
	[logger setSuccess:NO];
	[logger setDuration:[finishTime timeIntervalSinceDate:startTime]];
	[STUNTUtilities sendStuntFeedback:logger];
	
	[self cleanup];
}

- (void)cleanup
{
	DDLogVerbose(@"STUNTSocket: cleanup");
	
	// Remove self as port mapper observer.
	// We do this here so it gets done sooner rather than later.
	// It's also done in the dealloc method just in case the user never calls start.
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Remove our port mapping
	if(local_mappedServerPort > 0)
		 [[TCMPortMapper sharedInstance] removePortMapping:portMapping];
	else
		 [[NSApp delegate] removeServerPortMapping];
	
	// Remove self as xmpp delegate
	[[MojoXMPPClient sharedInstance] removeDelegate:self];
	
	// Remove self from existingStuntSockets dictionary so we can be deallocated
	[existingStuntSockets removeObjectForKey:uuid];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNTMessage

+ (BOOL)isStuntInviteMessage:(XMPPMessage *)message
{
	// Get x level information
	NSXMLElement *x = [message elementForName:@"x" xmlns:@"maestro:x:stunt"];
	if(x == nil)
	{
		x = [message elementForName:@"x" xmlns:@"deusty:x:stunt"];
	}
	
	if(x)
	{
		NSString *type = [[x attributeForName:@"type"] stringValue];
		
		return [type isEqualToString:@"invite"];
	}
	
	return NO;
}

+ (STUNTMessage *)messageFromMessage:(XMPPMessage *)message
{
	return [[[STUNTMessage alloc] initFromMessage:message] autorelease];
}

+ (STUNTMessage *)messageWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid
{
	return [[[STUNTMessage alloc] initWithType:type to:to uuid:uuid] autorelease];
}

- (id)initFromMessage:(XMPPMessage *)message
{
	if((self = [super init]))
	{
		// Initialize any variables that need initialization
		predictedPort = 0;
		serverPort = 0;
		
		// Get message level information: from and uuid
		from = [[message from] copy];
		uuid = [[message elementID] copy];
		
		// Get x level information
		NSXMLElement *x = [message elementForName:@"x"];
		
		type    = [[[x attributeForName:@"type"] stringValue] copy];
		version = [[[x attributeForName:@"version"] stringValue] copy];
		
		if(version == nil)
		{
			// If no version is specified, the base 1.0 version is assumed
			version = @"1.0";
		}
		
		// Get type specific information
		if([type isEqualToString:@"invite"] || [type isEqualToString:@"accept"])
		{
			ip4 = [[[x elementForName:@"ip"] stringValue] copy];
			ip6 = [[[x elementForName:@"ip6"] stringValue] copy];
			
			predictedPort = (UInt16)[[[x elementForName:@"port"] stringValue] intValue];
			serverPort    = (UInt16)[[[x elementForName:@"serverPort"] stringValue] intValue];
			
			// Note: We puposely cast as UInt16 to ensure it's a valid port number
		}
		else if([type isEqualToString:@"error"])
		{
			errorMessage = [[[x elementForName:@"message"] stringValue] copy];
		}
	}
	return self;
}

- (id)initWithType:(NSString *)aType to:(XMPPJID *)toJid uuid:(NSString *)aUUID
{
	if((self = [super init]))
	{
		type = [aType copy];
		to   = [toJid copy];
		uuid = [aUUID copy];
		
		version = STUNT_VERSION;
		
		// Initialize any variables that need initialization
		predictedPort = 0;
		serverPort = 0;
	}
	return self;
}

- (void)dealloc
{
	[to release];
	[from release];
	[uuid release];
	
	[type release];
	[version release];
	
	[ip4 release];
	[ip6 release];
	
	[errorMessage release];
	
	[super dealloc];
}

- (XMPPJID *)to {
	return to;
}

- (XMPPJID *)from {
	return from;
}

- (NSString *)uuid {
	return uuid;
}

- (NSString *)type {
	return type;
}

- (NSString *)version {
	return version;
}

- (NSString *)ip4 {
	return ip4;
}
- (void)setIP4:(NSString *)newIP4
{
	if(![ip4 isEqualToString:newIP4])
	{
		[ip4 release];
		ip4 = [newIP4 copy];
	}
}

- (NSString *)ip6 {
	return ip6;
}
- (void)setIP6:(NSString *)newIP6
{
	if(![ip6 isEqualToString:newIP6])
	{
		[ip6 release];
		ip6 = [newIP6 copy];
	}
}

- (int)predictedPort {
	return predictedPort;
}
- (void)setPredictedPort:(int)port {
	predictedPort = port;
}

- (int)serverPort {
	return serverPort;
}
- (void)setServerPort:(int)port {
	serverPort = port;
}

- (NSString *)errorMessage {
	return errorMessage;
}
- (void)setErrorMessage:(NSString *)msg
{
	if(![errorMessage isEqualToString:msg])
	{
		[errorMessage release];
		errorMessage = [msg copy];
	}
}

- (NSXMLElement *)xmlElement
{
	NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"maestro:x:stunt"];
	[x addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:type]];
	[x addAttribute:[NSXMLNode attributeWithName:@"version" stringValue:version]];
	
	if([type isEqualToString:@"invite"] || [type isEqualToString:@"accept"])
	{
		if(ip4)
		{
			[x addChild:[NSXMLNode elementWithName:@"ip" stringValue:ip4]];
		}
		if(ip6)
		{
			[x addChild:[NSXMLNode elementWithName:@"ip6" stringValue:ip6]];
		}
		if(predictedPort > 0)
		{
			NSString *predictedPortStr = [NSString stringWithFormat:@"%i", predictedPort];
			[x addChild:[NSXMLNode elementWithName:@"port" stringValue:predictedPortStr]];
		}
		if(serverPort > 0)
		{
			NSString *serverPortStr = [NSString stringWithFormat:@"%i", serverPort];
			[x addChild:[NSXMLNode elementWithName:@"serverPort" stringValue:serverPortStr]];
		}
	}
	else if([type isEqualToString:@"error"])
	{
		[x addChild:[NSXMLNode elementWithName:@"message" stringValue:errorMessage]];
	}
	
	NSXMLElement *message = [NSXMLElement elementWithName:@"message"];
	[message addAttribute:[NSXMLNode attributeWithName:@"to" stringValue:[to full]]];
	[message addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:uuid]];
	[message addChild:x];
	
	return message;
}

@end
