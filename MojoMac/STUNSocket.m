/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "STUNSocket.h"
#import "STUNUtilities.h"
#import "AsyncUdpSocket.h"
#import "NSDataAdditions.h"
#import "MojoXMPPClient.h"

#import <TCMPortMapper/TCMPortMapper.h>

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

// STUN protocol version
#define STUN_VERSION  @"1.1"

// Define states
#define STATE_INIT              0
#define STATE_START             1
#define STATE_INVITE_SENT       2
#define STATE_ACCEPT_SENT       3
#define STATE_PORT_PREDICTION   4
#define STATE_VALIDATION_STD    5
#define STATE_VALIDATION_PS1    6
#define STATE_VALIDATION_PS2    7
#define STATE_WAIT              8
#define STATE_DONE              9
#define STATE_FAILURE          10

// Define various timeouts
#define NO_TIMEOUT                     -1.0
#define STD_VALIDATION_TIMEOUT          9.0
#define PS1_VALIDATION_TIMEOUT          7.0
#define PS2_VALIDATION_CLIENT_TIMEOUT   7.0
#define PS2_VALIDATION_SERVER_TIMEOUT  16.0

// Define the number of sockets to use for PS-STUN 2
#define NUM_PS2_SOCKETS        20

// Define the different validation techniques
#define VALIDATION_TYPE_NORMAL  0
#define VALIDATION_TYPE_PS1     1
#define VALIDATION_TYPE_PS2     2

// Define the different probes
// When converted to data, these must not have a length of 16 bytes
#define PROBE_PS1  @"ps-stun-1 probe"
#define PROBE_PS2  @"ps-stun-2 probe"

// Host and Port of STUN server (previously @"numb.viagenie.ca")
#define STUN_SERVER_HOST  @"deusty.com"
#define STUN_SERVER_PORT  3478

// Number of connection attempts for PS-STUN algorithms
#define MAX_ATTEMPTS  3

// Timeout for the entire STUN procedure
// This ensures that in the event a peer crashes, the STUNSocket object won't reside in memory forever
#define TIMEOUT_TOTAL    35.00

// Declare private methods
@interface STUNSocket (PrivateAPI)
- (void)performPostInitSetup;
- (void)startNatDiscovery;
- (void)processDiscoveryResponse:(STUNMessage *)response;
- (void)startPortPrediction;
- (void)processPredictionResponse:(STUNMessage *)response;
- (void)startValidation;
- (void)startPS1Validation;
- (void)startPS2Validation;
- (void)restartIncomingValidation;
- (void)restartOutgoingValidation;
- (void)succeedWithSocket:(AsyncUdpSocket *)sock host:(NSString *)host port:(UInt16)port;
- (void)fail;
- (void)cleanup;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNSocket

static NSMutableDictionary *existingStunSockets;

/**
 * Called automatically (courtesy of Cocoa) before the first method of this class is called.
 * It may also be called directly, hence the safety mechanism.
**/
+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		existingStunSockets = [[NSMutableDictionary alloc] init];
	}
}

+ (BOOL)isNewStartStunMessage:(XMPPMessage *)msg
{
	if([STUNXMPPMessage isStunInviteMessage:msg])
	{
		NSString *uuid = [msg elementID];
		
		if([existingStunSockets objectForKey:uuid])
			return NO;
		else
			return YES;
	}
	return NO;
}

+ (NSString *)routerTypeToMappingString:(RouterType)routerType
{
	switch(routerType)
	{
		case ROUTER_TYPE_NONE                      : return @"None";
		case ROUTER_TYPE_CONE_FULL                 : return @"Cone";
		case ROUTER_TYPE_CONE_RESTRICTED           : return @"Cone";
		case ROUTER_TYPE_CONE_PORT_RESTRICTED      : return @"Cone";
		case ROUTER_TYPE_SYMMETRIC_FULL            : return @"Symmetric";
		case ROUTER_TYPE_SYMMETRIC_RESTRICTED      : return @"Symmetric";
		case ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED : return @"Symmetric";
		default                                    : return @"Unknown";
	}
}

+ (NSString *)routerTypeToFilteringString:(RouterType)routerType
{
	switch(routerType)
	{
		case ROUTER_TYPE_NONE                      : return @"None";
		case ROUTER_TYPE_CONE_FULL                 : return @"Full";
		case ROUTER_TYPE_CONE_RESTRICTED           : return @"Restricted";
		case ROUTER_TYPE_CONE_PORT_RESTRICTED      : return @"Port Restricted";
		case ROUTER_TYPE_SYMMETRIC_FULL            : return @"Full";
		case ROUTER_TYPE_SYMMETRIC_RESTRICTED      : return @"Restricted";
		case ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED : return @"Port Restricted";
		default                                    : return @"Unknown";
	}
}

+ (NSString *)stringFromRouterType:(RouterType)routerType
{
	switch(routerType)
	{
		case ROUTER_TYPE_NONE                      : return STR_ROUTER_TYPE_NONE;
		case ROUTER_TYPE_CONE_FULL                 : return STR_ROUTER_TYPE_CONE_FULL;
		case ROUTER_TYPE_CONE_RESTRICTED           : return STR_ROUTER_TYPE_CONE_RESTRICTED;
		case ROUTER_TYPE_CONE_PORT_RESTRICTED      : return STR_ROUTER_TYPE_CONE_PORT_RESTRICTED;
		case ROUTER_TYPE_SYMMETRIC_FULL            : return STR_ROUTER_TYPE_SYMMETRIC_FULL;
		case ROUTER_TYPE_SYMMETRIC_RESTRICTED      : return STR_ROUTER_TYPE_SYMMETRIC_RESTRICTED;
		case ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED : return STR_ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED;
		default                                    : return STR_ROUTER_TYPE_UNKNOWN;
	}
}

+ (RouterType)routerTypeFromString:(NSString *)rtStr
{
	if([rtStr isEqualToString:STR_ROUTER_TYPE_NONE])                      return ROUTER_TYPE_NONE;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_CONE_FULL])                 return ROUTER_TYPE_CONE_FULL;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_CONE_RESTRICTED])           return ROUTER_TYPE_CONE_RESTRICTED;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_CONE_PORT_RESTRICTED])      return ROUTER_TYPE_CONE_PORT_RESTRICTED;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_SYMMETRIC_FULL])            return ROUTER_TYPE_SYMMETRIC_FULL;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_SYMMETRIC_RESTRICTED])      return ROUTER_TYPE_SYMMETRIC_RESTRICTED;
	if([rtStr isEqualToString:STR_ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED]) return ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED;
	
	return ROUTER_TYPE_UNKNOWN;
}

static NSString *StringFromState(int state)
{
	switch(state)
	{
		case STATE_INIT            : return @"STATE_INIT";
		case STATE_START           : return @"STATE_START";
		case STATE_INVITE_SENT     : return @"STATE_INVITE_SENT";
		case STATE_ACCEPT_SENT     : return @"STATE_ACCEPT_SENT";
		case STATE_PORT_PREDICTION : return @"STATE_PORT_PREDICTION";
		case STATE_VALIDATION_STD  : return @"STATE_VALIDATION_STD";
		case STATE_VALIDATION_PS1  : return @"STATE_VALIDATION_PS1";
		case STATE_VALIDATION_PS2  : return @"STATE_VALIDATION_PS2";
		case STATE_WAIT            : return @"STATE_WAIT";
		case STATE_DONE            : return @"STATE_DONE";
		case STATE_FAILURE         : return @"STATE_FAILURE";
	}
	
	return @"STATE_UNKNOWN";
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes a new STUN socket to create a UDP connection by traversing NAT's and/or firewalls.
 * This constructor configures the object to be the client connecting to a server.
 * Therefore it will start out life as the Active Endpoint.
**/
- (id)initWithJID:(XMPPJID *)aJID
{
	if((self = [super init]))
	{
		// Retain a references to the JID
		jid = [aJID retain];
		
		// Create a uuid to be used as the id for all messages in the stun communication.
		// This helps differentiate various stun messages between various stun sockets.
		// Relying only on JID's is troublesome, because client A could be initiating a connection to server B,
		// while at the same time client B could be initiating a connection to server A.
		// So an incoming connection from JID clientB@deusty.com/home would be for which stun socket?
		CFUUIDRef theUUID = CFUUIDCreate(NULL);
		uuid = (NSString *)CFUUIDCreateString(NULL, theUUID);
		CFRelease(theUUID);
		
		// Setup initial state for a client connection
		state = STATE_INIT;
		isClient = YES;
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Initializes a new STUN socket to create a UDP connection by traversing NAT's and/or firewalls.
 * This constructor configures the object to be the server accepting a connection from a client,
 * and will thus start out as the passive endpoint.
**/
- (id)initWithStunMessage:(XMPPMessage *)message
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
		STUNXMPPMessage *stunXmppMessage = [STUNXMPPMessage messageFromMessage:message];
		
		remote_routerType   = [stunXmppMessage routerType];
		remote_externalIP   = [[stunXmppMessage ip] copy];
		remote_externalPort = [stunXmppMessage port];
		
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
	// Initialize attempt count
	attemptCount = 0;
	
	// Initialize max round trip time
	maxRtt = 0.0;
	
	// Initialize empty ranges
	local_externalPortRange = NSMakeRange(0, 0);
	remote_externalPortRange = NSMakeRange(0, 0);
	
	// Initialize validation variables
	readValidationFailed = NO;
	readValidationComplete = NO;
	writeValidationComplete = NO;
	
	// Initialize stunt logger
	logger = [[STUNLogger alloc] initWithSTUNUUID:uuid version:STUN_VERSION];
	
	// We want to add this new stun socket to the list of existing sockets.
	// This gives us a central repository of stun socket objects that we can easily query.
	[existingStunSockets setObject:self forKey:uuid];
	
	// Initialize udp socket - we're only going to be using IPv4 for now
	udpSocket = [[AsyncUdpSocket alloc] initIPv4];
	[udpSocket setDelegate:self];
	[udpSocket setMaxReceiveBufferSize:256];
}

/**
 * Standard deconstructor.
 * Release any objects we may have retained.
 * These objects should all be defined in the header.
**/
- (void)dealloc
{
	DDLogVerbose(@"STUNSocket: dealloc: %p", self);
	
	[jid release];
	[uuid release];
	
	[currentStunMessage release];
	[currentStunMessageDestinationHost release];
	[currentStunMessageFirstSentTime release];
	
	[altStunServerIP release];
	[local_externalIP release];
	[remote_externalIP release];
	
	if([udpSocket delegate] == self)
	{
		[udpSocket setDelegate:nil];
		[udpSocket close];
	}
	[udpSocket release];
	
	int i;
	for(i = 0; i < [scanningSockets count]; i++)
	{
		AsyncUdpSocket *socket = [scanningSockets objectAtIndex:i];
		
		if([socket delegate] == self)
		{
			[socket setDelegate:nil];
			[socket close];
		}
	}
	[scanningSockets release];
	
	[validationData release];
	[validationTimer invalidate];
	[validationTimer release];
	[restartIncomingValidationDate release];
	
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
	
	// Update state
	state = STATE_START;
	
	// Add self as xmpp delegate so we'll get stun message responses
	[[MojoXMPPClient sharedInstance] addDelegate:self];
	
	// Start the timer to calculate how long the procedure takes
	startTime = [[NSDate alloc] init];
	
	NSString *hardwareAddr = [[TCMPortMapper sharedInstance] routerHardwareAddress];
	NSString *routerManufacturer = [TCMPortMapper manufacturerForHardwareAddress:hardwareAddr];
	
	[logger setRouterManufacturer:routerManufacturer];
	
	if(isClient)
	{
		[self startNatDiscovery];
	}
	else
	{
		[logger addTraceMessage:@"remote=%@", [[self class] stringFromRouterType:remote_routerType]];
		
		if(remote_routerType == ROUTER_TYPE_NONE || remote_routerType == ROUTER_TYPE_CONE_FULL)
		{
			// We won't bother with NAT discovery, because the remote router is fully non-restrictive.
			// We can immediately start sending our validation data.
			[self startValidation];
		}
		else
		{
			// The remote host needs to know a bit of information about us
			[self startNatDiscovery];
		}
	}
	
	// Schedule timeout timer to cancel the stun procedure.
	// This ensures that, in the event of network error or crash,
	// the STUNSocket object won't remain in memory forever, and will eventually fail.
	[NSTimer scheduledTimerWithTimeInterval:TIMEOUT_TOTAL
									 target:self
								   selector:@selector(doTotalTimeout:)
								   userInfo:nil
									repeats:NO];
}

/**
 * This method returns the UUID (Universally Unique Identifier) that is associated with this StunSocket instance.
 * This is the value that will be used as the ID attribute of all outgoing and incoming messages associated
 * with this StunSocket.
 * It may be used to map incoming XMPP messages to the proper StunSocket.
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
 * Aborts the STUN connection attempt.
 * The status will be changed to failure, and no delegate messages will be posted.
**/
- (void)abort
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	if(state != STATE_INIT)
	{
		// The only thing we really have to do here is move the state to failure.
		// This simple act should prevent any further action from being taken in this STUNSocket object,
		// since every action is dictated based on the current state.
		state = STATE_FAILURE;
		
		// And don't forget to cleanup after ourselves
		[self cleanup];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Communication
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)sendSTUNXMPPMessage:(STUNXMPPMessage *)message
{
	[[MojoXMPPClient sharedInstance] sendElement:[message xmlElement]];
}

- (void)sendInviteMessage
{
	NSAssert(isClient, @"PE trying to send invite message");
	
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"invite" to:jid uuid:uuid];
	[msg setRouterType:local_routerType];
	[msg setIP:local_externalIP];
	[msg setPort:local_externalPort];
	
	[self sendSTUNXMPPMessage:msg];
	
	// Update state
	state = STATE_INVITE_SENT;
}

- (void)sendAcceptMessage
{
	NSAssert(!isClient, @"AE trying to send accept message");
	
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"accept" to:jid uuid:uuid];
	[msg setRouterType:local_routerType];
	[msg setIP:local_externalIP];
	[msg setPort:local_externalPort];
	
	if(local_externalPortRange.location != 0)
	{
		[msg setPortRange:local_externalPortRange];
	}
	
	[self sendSTUNXMPPMessage:msg];
	
	// Update state
	state = STATE_ACCEPT_SENT;
}

- (void)sendCallbackMessage
{
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"callback" to:jid uuid:uuid];
	[msg setPort:local_externalPort];
	
	if(local_externalPortRange.location != 0)
	{
		[msg setPortRange:local_externalPortRange];
	}
	
	[self sendSTUNXMPPMessage:msg];
	
	// We do not update state
	// This method could be called for various reasons
}

/**
 * Sends reset messate to the remote host, to let them know we need to try again.
**/
- (void)sendResetMessage
{
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"reset" to:jid uuid:uuid];
	
	[self sendSTUNXMPPMessage:msg];
	
	// We do not update state
	// This method could be called for various reasons
}

/**
 * Sends a failure message, indicating that 
**/
- (void)sendFailMessage
{
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"fail" to:jid uuid:uuid];
	[msg setErrorMessage:@"Exceeded max number of attempts"];
	
	[self sendSTUNXMPPMessage:msg];
	
	// We do not update state
	// This method could be called for various reasons
}

/**
 * Sends validated message to the remote host, to let them know their validation message has been accepted.
 * This allows them to stop retransmitting it.
**/
- (void)sendValidatedMessage
{
	STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"validated" to:jid uuid:uuid];
	
	[self sendSTUNXMPPMessage:msg];
	
	// We do not update state
	// This method could be called for various reasons
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
		// It's not a stun message or it's for another stun socket
		return;
	}
	
	STUNXMPPMessage *message = [STUNXMPPMessage messageFromMessage:msg];
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:@"%@, message=%@", StringFromState(state), [message type]];
	
	if(state == STATE_INVITE_SENT)
	{
		// An accept message is only sent when our router type is more restrictive than full cone
		if(local_routerType == ROUTER_TYPE_NONE || local_routerType == ROUTER_TYPE_CONE_FULL)
		{
			DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_INVITE_SENT: %@", [message type]);
			return;
		}
		
		if([[message type] isEqualToString:@"accept"])
		{
			// This is the first message we've received from the remote host
			
			remote_routerType = [message routerType];
			remote_externalIP = [[message ip] copy];
			remote_externalPort = [message port];
			remote_externalPortRange = [message portRange];
			
			[logger addTraceMessage:@"remote=%@", [[self class] stringFromRouterType:remote_routerType]];
			
			if(local_routerType == ROUTER_TYPE_CONE_RESTRICTED)
			{
				// Our router is very permissive - all we need to do is send data to the IP once,
				// and then we'll be able to receive data from any of their ports.
				[self startValidation];
			}
			else if(local_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
			{
				// Our router is cone port restricted
				
				if(remote_routerType <= ROUTER_TYPE_CONE_PORT_RESTRICTED)
				{
					// The remote router is non-symmetric
					[self startValidation];
				}
				else
				{
					// The remote router is symmetric
					[self startPS1Validation];
				}
			}
			else
			{
				// Our router is symmetric
				
				if(remote_routerType <= ROUTER_TYPE_CONE_RESTRICTED)
				{
					// It doesn't matter what external port we're given,
					// we should still be able to connect to the remote host easily.
					[self startValidation];
				}
				else if(remote_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
				{
					// The remote host needs our port predictions
					[self startPortPrediction];
				}
				else
				{
					// Bad news - the remote host is also symmetric.
					// We're both going to have to do port prediction,
					// and use a bunch of UDP sockets to attempt a connection.
					[self startPortPrediction];
				}
			}
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
	else if(state == STATE_ACCEPT_SENT)
	{
		if([[message type] isEqualToString:@"callback"])
		{
			remote_externalPort = [message port];
			remote_externalPortRange = [message portRange];
			
			[self startPS1Validation];
		}
		else
		{
			DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_ACCEPT_SENT: %@", [message type]);
		}
	}
	else if(state == STATE_PORT_PREDICTION)
	{
		if([[message type] isEqualToString:@"callback"])
		{
			remote_externalPort = [message port];
			remote_externalPortRange = [message portRange];
			
			if(local_externalPort > 0)
			{
				// We're done with port prediction, and we just received word they are too.
				// Time to start PS-STUN algorithm 2
				[self startPS2Validation];
			}
		}
		else
		{
			DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_PORT_PREDICTION: %@", [message type]);
		}
	}
	else if(state == STATE_VALIDATION_STD || state == STATE_VALIDATION_PS1 || state == STATE_VALIDATION_PS2)
	{
		// We're waiting for either a validated message, or possibly a reset message
		
		// Check to see if it's a validated message
		// - AND -
		// that we haven't already received such a message in the past
		
		if([[message type] isEqualToString:@"validated"] && !writeValidationComplete)
		{
			// The remote host has acknowledged receipt of our UDP validation message
			writeValidationComplete = YES;
			
			// We can stop sending validation data
			[validationTimer invalidate];
			[validationTimer release];
			validationTimer = nil;
			
			// Wait for all IO to complete before we hand the socket over to others
			if(readValidationComplete && writeValidationComplete)
			{
				[self succeedWithSocket:udpSocket host:remote_externalIP port:remote_externalPort];
			}
			else
			{
				if(state == STATE_VALIDATION_STD)
				{
					// The remote host may have only just learned of our ip and/or port.
					[self restartIncomingValidation];
				}
				else if(state == STATE_VALIDATION_PS1)
				{
					// We received a VALIDATED receipt, meaning the other side has received our validation packet.
					
					// Only the side with the "Cone - Port Restricted" router will arrive at this point.
					// This is because this side is the only side sending validation data.
					// The symmetric side was only sending probes initially.
					
					// We were scanning through the port range they sent us, and one of our packets got through.
					// We should now be able to receive data from the remote host.
					[self restartIncomingValidation];
					
					// Note: the restartIncomingValidation method will switch us to STATE_VALIDATION_STD, and
					// will request a receive for us from the udp socket.
				}
				else
				{
					// We received a VALIDATED receipt, meaning the other side has received our validation packet.
					
					// It is technically possible for either the client or server to arrive at this point,
					// but it is most likely the server.
					// This is because the client doesn't even start sending its validation until after
					// it has received validation from the server.
					// The client side was only sending probes initially.
					
					// One of our packets got through to the other host.
					// This means that one of our sockets should be able to receive data from them.
					[self restartIncomingValidation];
					
					// Note: the restartIncomingValidation method will properly extend incoming validation for
					// for all opened sockets in the scanningSockets array.
				}
			}
		}
		else if([[message type] isEqualToString:@"reset"])
		{
			if(state == STATE_VALIDATION_PS1)
			{
				// Only symmetric side is supposed to send reset message in PS1
				
				if(local_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
				{
					// Update state
					state = STATE_WAIT;
					
					// Stop sending validation messages
					[validationTimer invalidate];
					[validationTimer release];
					validationTimer = nil;
					
					DDLogVerbose(@"STUNSocket: Received reset msg, waiting for callback msg...");
				}
				else
				{
					DDLogWarn(@"STUNSocket: Only symmetric side is supposed to send reset msg in PS1");
				}
			}
			else if(state == STATE_VALIDATION_PS2)
			{
				// Only client side is supposed to send reset message in PS2
				
				if(!isClient)
				{
					// Stop sending validation messages
					[validationTimer invalidate];
					[validationTimer release];
					validationTimer = nil;
					
					// Dump the scanning sockets
					uint i;
					for(i = 0; i < [scanningSockets count]; i++)
					{
						AsyncUdpSocket *socket = [scanningSockets objectAtIndex:i];
						
						[socket setDelegate:nil];
						[socket close];
					}
					[scanningSockets release];
					scanningSockets = nil;
					
					DDLogVerbose(@"STUNSocket: Received reset msg, restarting port prediction...");
					
					// And start port prediction again
					[self startPortPrediction];
				}
				else
				{
					DDLogWarn(@"STUNSocket: Only client side is supposed to send reset msg in PS2");
				}
			}
		}
		else if([[message type] isEqualToString:@"fail"])
		{
			// We received an error message
			[logger setFailureReason:[NSString stringWithFormat:@"RCV: %@", [message errorMessage]]];
			[self fail];
		}
		else if(DEBUG_WARN)
		{
			if(state == STATE_VALIDATION_STD)
			{
				DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_VALIDATION_STD: %@", [message type]);
			}
			else if(state == STATE_VALIDATION_PS1)
			{
				DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_VALIDATION_PS1: %@", [message type]);
			}
			else
			{
				DDLogWarn(@"STUNSocket: Received unexpected message while in STATE_VALIDATION_PS2: %@", [message type]);
			}
		}
	}
	else if(state == STATE_WAIT)
	{
		if([[message type] isEqualToString:@"callback"])
		{
			remote_externalPort = [message port];
			remote_externalPortRange = [message portRange];
			
			[self startPS1Validation];
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
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Handles retransmissions of binding requests, incrementing the timeout as needed,
 * and failing if max timeout is reached.
**/
- (void)maybeResendCurrentStunMessage
{
	// The STUN RFC specified doubling the timeout each time, up to 1.6 seconds,
	// and waiting a full 9.5 seconds for a request to timeout:
	// 
	// Send time:   0ms > 100ms > 300ms >  700ms > 1500ms > 3100ms > 4700ms > 6300ms > 7900ms 
	// Wait time: 100ms > 200ms > 400ms >  800ms > 1600ms > 1600ms > 1600ms > 1600ms > 1600ms
	// Ellapsed : 100ms > 300ms > 700ms > 1500ms > 3100ms > 4700ms > 6300ms > 7900ms > 9500ms
	// 
	// This seems ridiculous considering that binding requests are often expected to fail.
	// If binding requests are failing often, and 9.5 second timeouts are used, the procedure could take a long time!
	// For this reason, we may wait a shorter amount of time based on previous recorded RTT times.
	// This results in a shorter failure time, while maintaining reasonable timeout durations.
	
	currentStunMessageElapsed += currentStunMessageTimeout;
	if(currentStunMessageTimeout < 1.6)
	{
		currentStunMessageTimeout = currentStunMessageTimeout * 2.0;
	}
	
	NSTimeInterval maxTime = 9.5;
	if(maxRtt > 0.0)
	{
		if(maxRtt < 1.0)
		{
			maxTime = 1.5;
		}
		else if(maxRtt < 2.0)
		{
			maxTime = 3.1;
		}
		else if(maxRtt < 3.5)
		{
			maxTime = 4.7;
		}
		else if(maxRtt < 5.0)
		{
			maxTime = 6.3;
		}
		else if(maxRtt < 6.5)
		{
			maxTime = 7.9;
		}
	}
	
	if(currentStunMessageElapsed < maxTime)
	{
		DDLogVerbose(@"STUNSocket: Resending binding request");
		
		// Resend binding request
		[udpSocket sendData:[currentStunMessage messageData]
					 toHost:currentStunMessageDestinationHost
					   port:currentStunMessageDestinationPort
				withTimeout:NO_TIMEOUT
						tag:currentStunMessageNumber];
		
		// Restart receiving binding response
		[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	}
	else
	{
		// Timed out
		if(state == STATE_START)
			[self processDiscoveryResponse:nil];
		else
			[self processPredictionResponse:nil];
	}
}

/**
 * When a port range is given, the ports are not tried linearly.
 * Instead we make use of the predicted port, assuming that it's most likely succeed.
 * So the first port we try is the predicted port.
 * Then we try the ports immediately next to it, then the one immediately next to them, and so on.
 * 
 * Eg: getPort:0 fromRange:(2000,10) withPredictedPort:2002 --> 2002
 *     getPort:1 fromRange:(2000,10) withPredictedPort:2002 --> 2003
 *     getPort:2 fromRange:(2000,10) withPredictedPort:2002 --> 2001
 *     getPort:3 fromRange:(2000,10) withPredictedPort:2002 --> 2004
 *     getPort:4 fromRange:(2000,10) withPredictedPort:2002 --> 2000
 *     getPort:5 fromRange:(2000,10) withPredictedPort:2002 --> 2005
 *     getPort:2 fromRange:(2000,10) withPredictedPort:2002 --> 2006
**/
- (UInt16)getPort:(unsigned)index fromRange:(NSRange)range withPredictedPort:(UInt16)predictedPort
{
	// Ensure valid parameters
	if(!NSLocationInRange(predictedPort, range) || index >= range.length) return predictedPort;
	
	// Shortcut for the obvious one
	if(index == 0) return predictedPort;
	
	// Calculate number of values below and above the predictedPort within the range
	int low = predictedPort - range.location;
	int high = range.location + range.length - 1 - predictedPort;
	
	if(index % 2 == 1)
	{
		int highIndex = (int)((index + 1) / 2);
		
		if(highIndex > high)
		{
			// Ran out of high numbers
			return predictedPort - index + high;
		}
		else if(highIndex <= low)
		{
			// Have not yet run out of high numbers or low number
			return predictedPort + highIndex;
		}
		else
		{
			// Already ran out of low numbers
			return predictedPort - low + index;
		}
	}
	else
	{
		int lowIndex = (int)(index / 2);
		
		if(lowIndex > low)
		{
			// Ran out of low numbers
			return predictedPort + index - low;
		}
		else if(lowIndex <= high)
		{
			// Have not yet run out of low numbers or high numbers
			return predictedPort - lowIndex;
		}
		else
		{
			// Already ran out of high numbers
			return predictedPort + high - index;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NAT Discovery
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sends discovery binding request 1: Regular stun server, no IP change, no port change.
 * This is the first binding request, and is always sent.
**/
- (void)startDiscoveryRequest1
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 1");
	
	// Setup stun binding request message
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = STUN_SERVER_HOST;
	currentStunMessageDestinationPort = STUN_SERVER_PORT;
	
	// Reset related stun variables
	currentStunMessageNumber = 1;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Sends binding request 2: Regular stun server, change IP, change port.
 * This is the second binding request, and is always sent if the user needs to discover his/her NAT type.
**/
- (void)startDiscoveryRequest2
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 2");
	
	// Setup stun binding request
	STUNChangeAttribute *changeAttr = [[[STUNChangeAttribute alloc] initWithChangeIP:YES changePort:YES] autorelease];
	
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	[currentStunMessage addAttribute:changeAttr];
	
	currentStunMessageDestinationHost = STUN_SERVER_HOST;
	currentStunMessageDestinationPort = STUN_SERVER_PORT;
	
	// Reset related stun variables
	currentStunMessageNumber = 2;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Sends binding request 3: Alternate stun server, no IP change, no port change.
 * This request is sent if we didn't receive binding response 2.
**/
- (void)startDiscoveryRequest3
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 3");
	
	// Setup stun binding request
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 3;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request (to alternate stun server)
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Sends binding request 4: Alternate stun server, no IP change, change port.
 * This is sent if binding response 3 showed the NAT to be non-symmetric.
**/
- (void)startDiscoveryRequest4
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 4");
	
	// Setup stun binding request
	STUNChangeAttribute *changeAttr = [[[STUNChangeAttribute alloc] initWithChangeIP:NO changePort:YES] autorelease];
	
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	[currentStunMessage addAttribute:changeAttr];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 4;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request (to alternate stun server)
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Sends binding request 5: Alternate stun server, no IP change, no port change.
 * This is sent if binding response 2 was received successfully.
**/
- (void)startDiscoveryRequest5
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 5");
	
	// Setup stun binding request
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 5;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request (to alternate stun server)
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Sends binding request 6: Alternate stun server, no IP change, change port.
 * This is sent if binding response 3 showed the NAT to be symmetric.
**/
- (void)startDiscoveryRequest6
{
	DDLogVerbose(@"STUNSocket: Starting Discovery Request 6");
	
	// Setup stun binding request
	STUNChangeAttribute *changeAttr = [[[STUNChangeAttribute alloc] initWithChangeIP:NO changePort:YES] autorelease];
	
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	[currentStunMessage addAttribute:changeAttr];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 6;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request (to alternate stun server)
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Starts the NAT discovery process.
**/
- (void)startNatDiscovery
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// No need to update state here
	// STATE_START = NAT discovery
	
	[self startDiscoveryRequest1];
}

/**
 * Processes the binding response from binding request 1.
 * This was a binding request to the regular stun server (A1:P1),
 * and the response was set to come from the regular ip and regular port (A1:P1).
**/
- (void)processDiscoveryResponse1:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 1: \n%@", response);
	
	// Test 1: Server 1 - IP(0), Port(0)
	
	// This is the only place where we record our external mapped address.
	// Check to see if the router is being naughty, and tattle if it is.
	
	STUNAddressAttribute *mappedAddress = [response mappedAddress];
	STUNAddressAttribute *xorMappedAddress = [response xorMappedAddress];
	
	STUNAddressAttribute *externalAddress = mappedAddress;
	
	if(xorMappedAddress)
	{
		if(![[mappedAddress address] isEqualToString:[xorMappedAddress address]])
		{
			DDLogWarn(@"STUNSocket: Router is rewriting mapped address");
			
			[logger setXorNeeded:YES];
			externalAddress = xorMappedAddress;
		}
	}
	
	if(externalAddress)
	{
		// Store alternate IP and port
		STUNAddressAttribute *changedAddress = [response changedAddress];
		
		altStunServerIP = [[changedAddress address] copy];
		altStunServerPort = [changedAddress port];
		
		// Store mapped address information
		local_externalIP = [[externalAddress address] copy];
		local_externalPort = [externalAddress port];
		
		if(isClient)
		{
			// Continue to test 2
			[self startDiscoveryRequest2];
		}
		else
		{
			// If we're here, then the remote router type is something above full cone.
			// That is, it's either cone restricted, cone port restricted, or symmetric.
			// 
			// If the remote router type is cone restricted, then we can stop here, and send our accept.
			// That's because the remote host only needs to know our IP address to punch a hole in its router.
			
			if(remote_routerType == ROUTER_TYPE_CONE_RESTRICTED)
			{
				// We don't need to continue NAT discovery.
				// We just need to inform the client of our external IP address.
				
				// Set a local_routerType just to be safe
				local_routerType = ROUTER_TYPE_UNKNOWN;
				
				[self sendAcceptMessage];
				[self startValidation];
			}
			else
			{
				// Continue to test 2
				[self startDiscoveryRequest2];
			}
		}
	}
	else
	{
		// It looks as if UDP is completely blocked
		DDLogError(@"STUNSocket: Discovery request 1 failed");
		
		if(!isClient)
		{
			STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"error" to:jid uuid:uuid];
			[msg setErrorMessage:@"Discovery request 1 failed"];
			
			[self sendSTUNXMPPMessage:msg];
		}
		
		[logger setFailureReason:@"Discovery request 1 failed"];
		[self fail];
	}
}

/**
 * Processes the binding response from binding request 2.
 * This was a binding request sent to the regular stun server (A1:P1),
 * and the response was set to come from the alternate ip and alternate port (A2:P2).
**/
- (void)processDiscoveryResponse2:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 2: \n%@", response);
	
	// Test 2: Server 1 - IP(1), Port(1)
	
	if(response)
	{
		// This is good news - the router uses independent filtering.
		// It's still possible that the router doesn't use independent mapping though.
		
		[self startDiscoveryRequest5];
	}
	else
	{
		// We now know the router doesn't use independent filtering.
		// Continue the NAT discovery process - move onto test 3.
		[self startDiscoveryRequest3];
	}
}

/**
 * Processes the binding response from binding request 3.
 * This was a binding request sent to the alternate stun server (A2:P2),
 * and the response was set to come from the alternate ip and alternate port (A2:P2).
**/
- (void)processDiscoveryResponse3:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 3: \n%@", response);
	
	// Server 2 - IP(0), Port(0)
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
	
	if(externalAddress)
	{
		// Note: The local_externalPort variable was set from the first binding response
		
		if(local_externalPort == [externalAddress port])
		{
			// The router used our existing mapping to send data to a different IP and port.
			// This means we just need to figure out if it's cone restricted or cone port restricted.
			[self startDiscoveryRequest4];
		}
		else
		{
			// The router used a different mapping, even though we sent the data from the same IP and port.
			// In other words, it's symmetric - doesn't use independent mapping.
			// We still need to find out if it's restricted or port restricted.
			[self startDiscoveryRequest6];
		}
	}
	else
	{
		DDLogError(@"STUNSocket: Discovery request 3 failed");
		
		if(!isClient)
		{
			STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"error" to:jid uuid:uuid];
			[msg setErrorMessage:@"Discovery request 3 failed"];
			
			[self sendSTUNXMPPMessage:msg];
		}
		
		[logger setFailureReason:@"Discovery request 3 failed"];
		[self fail];
	}
}

/**
 * Processing the binding reponse from binding request 4.
 * This was a binding request sent to the alternate stun server (A2:P2),
 * and the response was set to come from the alternate ip and regular port (A2:P1).
**/
- (void)processDiscoveryResponse4:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 4: \n%@", response);
	
	// Server 2 - IP(0), Port(1)
	
	if(response)
	{
		// The router accepted a datagram from the same IP, but different port.
		// This means it's not restricted based on port.
		local_routerType = ROUTER_TYPE_CONE_RESTRICTED;
	}
	else
	{
		// The router doesn't accept datagrams unless we've already sent data to the same IP AND port.
		local_routerType = ROUTER_TYPE_CONE_PORT_RESTRICTED;
	}
	
	[logger addTraceMessage:@"local=%@", [[self class] stringFromRouterType:local_routerType]];
	
	if(isClient)
	{
		[self sendInviteMessage];
	}
	else
	{
		// If the remote host was CONE_FULL, then we wouldn't have performed NAT discovery.
		// If the remote host was CONE_RESTRICTED, then we would have stopped after the first binding response.
		
		if(remote_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
		{
			[self sendAcceptMessage];
			[self startValidation];
		}
		else
		{
			NSAssert((remote_routerType >= ROUTER_TYPE_SYMMETRIC_FULL), @"Remote router type isn't symmetric");
			
			if(local_routerType == ROUTER_TYPE_CONE_RESTRICTED)
			{
				[self sendAcceptMessage];
				[self startValidation];
			}
			else
			{
				[self sendAcceptMessage];
				
				// We don't start validation yet.
				// The remote host will need to perform port prediction first.
			}
		}
	}
}

/**
 * Processes the binding response from binding request 5.
 * This was a binding request sent to the alternate stun server (A2:P2),
 * and the response was set to come from the alternate ip and alternate port (A2:P2).
**/
- (void)processDiscoveryResponse5:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 5: \n%@", response);
	
	// Server 2 - IP(0), Port(0)
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
		
	if(externalAddress)
	{
		// Note: The local_externalPort variable was set from the first binding response
		
		if(local_externalPort == [externalAddress port])
		{
			NSString *local_internalIP = [udpSocket localHost];
			
			if([local_externalIP isEqualToString:local_internalIP])
			{
				local_routerType = ROUTER_TYPE_NONE;
			}
			else
			{
				local_routerType = ROUTER_TYPE_CONE_FULL;
			}
		}
		else
		{
			// Although there is no filtering, the router is still symmetric
			local_routerType = ROUTER_TYPE_SYMMETRIC_FULL;
		}
		
		[logger addTraceMessage:@"local=%@", [[self class] stringFromRouterType:local_routerType]];
		
		if(isClient)
		{
			[self sendInviteMessage];
			
			if(local_routerType == ROUTER_TYPE_NONE || local_routerType == ROUTER_TYPE_CONE_FULL)
			{
				// Our router is fully non-restrictive - the remote client can immediately begin sending us data.
				[self startValidation];
			}
		}
		else
		{
			if(remote_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
			{
				if(local_routerType == ROUTER_TYPE_SYMMETRIC_FULL)
				{
					[self startPortPrediction];
				}
				else
				{
					[self sendAcceptMessage];
					[self startValidation];
				}
			}
			else
			{
				NSAssert((remote_routerType >= ROUTER_TYPE_SYMMETRIC_FULL), @"Remote router type isn't symmetric");
				
				if(local_routerType == ROUTER_TYPE_SYMMETRIC_FULL)
				{
					[self sendAcceptMessage];
					[self startPortPrediction];
				}
				else
				{
					[self sendAcceptMessage];
					[self startValidation];
				}
			}
		}
	}
	else
	{
		DDLogError(@"STUNSocket: Discovery request 5 failed");
		
		if(!isClient)
		{
			STUNXMPPMessage *msg = [STUNXMPPMessage messageWithType:@"error" to:jid uuid:uuid];
			[msg setErrorMessage:@"Discovery request 5 failed"];
			
			[self sendSTUNXMPPMessage:msg];
		}
		
		[logger setFailureReason:@"Discovery request 5 failed"];
		[self fail];
	}
}

/**
 * Processing the binding reponse from binding request 6.
 * This was a binding request sent to the alternate stun server (A2:P2),
 * and the response was set to come from the alternate ip and regular port (A2:P1).
**/
- (void)processDiscoveryResponse6:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Discovery Response 6: \n%@", response);
	
	// Server 2 - IP(0), Port(1)
	
	if(response)
	{
		local_routerType = ROUTER_TYPE_SYMMETRIC_RESTRICTED;
	}
	else
	{
		local_routerType = ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED;
	}
	
	[logger addTraceMessage:@"local=%@", [[self class] stringFromRouterType:local_routerType]];
	
	if(isClient)
	{
		[self sendInviteMessage];
	}
	else
	{
		if(remote_routerType == ROUTER_TYPE_CONE_PORT_RESTRICTED)
		{
			[self startPortPrediction];
		}
		else
		{
			// If the remote router type was open or full cone, we wouldn't have bothered with nat discovery.
			// If the remote router type was restricted cone, we would have stopped after discovering our ip.
			// This means, given the previous if statement, the remote router is symmetric.
			NSAssert((remote_routerType >= ROUTER_TYPE_SYMMETRIC_FULL), @"Remote router type isn't symmetric");
			
			[self sendAcceptMessage];
			[self startPortPrediction];
		}
	}
}

/**
 * Processes the binding reponse according to the current stun binding request.
**/
- (void)processDiscoveryResponse:(STUNMessage *)response
{
	if(response)
	{
		// Record max round trip time
		NSTimeInterval rtt = [[NSDate date] timeIntervalSinceDate:currentStunMessageFirstSentTime];
		if(rtt > maxRtt)
		{
			maxRtt = rtt;
		}
	}
	
	// Release and nil currentStunMessage variables so multiple responses don't get processed again
	[currentStunMessage release];
	currentStunMessage = nil;
	
	[currentStunMessageDestinationHost release];
	currentStunMessageDestinationHost = nil;
	
	[currentStunMessageFirstSentTime release];
	currentStunMessageFirstSentTime = nil;
	
	switch(currentStunMessageNumber)
	{
		case 1 : [self processDiscoveryResponse1:response]; break;
		case 2 : [self processDiscoveryResponse2:response]; break;
		case 3 : [self processDiscoveryResponse3:response]; break;
		case 4 : [self processDiscoveryResponse4:response]; break;
		case 5 : [self processDiscoveryResponse5:response]; break;
		default: [self processDiscoveryResponse6:response]; break;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Port Prediction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Binding request to Primary IP, Primary Port (A1:P1)
**/
- (void)startPredictionRequest1
{
	DDLogVerbose(@"STUNSocket: Starting Prediction Request 1");
	
	// Setup stun binding request message
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = STUN_SERVER_HOST;
	currentStunMessageDestinationPort = STUN_SERVER_PORT;
	
	// Reset related stun variables
	currentStunMessageNumber = 101;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Binding request to Primary IP, Secondary Port (A1:P2)
**/
- (void)startPredictionRequest2
{
	DDLogVerbose(@"STUNSocket: Starting Prediction Request 2");
	
	// Setup stun binding request message
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = STUN_SERVER_HOST;
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 102;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Binding request to Secondary IP, Primary Port (A2:P1)
**/
- (void)startPredictionRequest3
{
	DDLogVerbose(@"STUNSocket: Starting Prediction Request 3");
	
	// Setup stun binding request message
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = STUN_SERVER_PORT;
	
	// Reset related stun variables
	currentStunMessageNumber = 103;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

/**
 * Binding request to Secondary IP, Secondary Port (A2:P2)
**/
- (void)startPredictionRequest4
{
	DDLogVerbose(@"STUNSocket: Starting Prediction Request 4");
	
	// Setup stun binding request message
	currentStunMessage = [[STUNMessage alloc] initWithType:STUN_BINDING_REQUEST];
	
	currentStunMessageDestinationHost = [altStunServerIP retain];
	currentStunMessageDestinationPort = altStunServerPort;
	
	// Reset related stun variables
	currentStunMessageNumber = 104;
	currentStunMessageElapsed = 0.0;
	currentStunMessageTimeout = 0.1;
	
	// Send the binding request
	[udpSocket sendData:[currentStunMessage messageData]
				 toHost:currentStunMessageDestinationHost
				   port:currentStunMessageDestinationPort
			withTimeout:NO_TIMEOUT
					tag:currentStunMessageNumber];
	
	// Start listening for the binding response
	// The short timeout is used to facilitate retransmissions
	[udpSocket receiveWithTimeout:currentStunMessageTimeout tag:currentStunMessageNumber];
	
	// Record time we first sent stun message
	currentStunMessageFirstSentTime = [[NSDate alloc] init];
}

- (void)startPortPrediction
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Update state
	state = STATE_PORT_PREDICTION;
	
	// We can't use our existing udp socket because the router already has mappings setup for it
	// We need to use a different internal port
	[udpSocket close];
	[udpSocket release];
	
	DDLogVerbose(@"STUNSocket: Creating new UDP socket for port prediction");
	
	udpSocket = [[AsyncUdpSocket alloc] initIPv4];
	[udpSocket setDelegate:self];
	[udpSocket setMaxReceiveBufferSize:256];
	
	if((local_routerType >= ROUTER_TYPE_SYMMETRIC_FULL) && (remote_routerType >= ROUTER_TYPE_SYMMETRIC_FULL))
	{
		// We're both going to be doing port prediction, and we can't start sending any udp data until
		// we've sent them our predictions, and they've sent us theirs.
		// So clear both our external port, and any external port they may have sent.
		// We also test these variables later to determine if it's time to start validation.
		local_externalPort = 0;
		remote_externalPort = 0;
	}
	
	// And start firing off the first binding request in the process
	[self startPredictionRequest1];
}

- (void)processPredictionResponse1:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Prediction Response 1: \n%@", response);
	
	// Test 1: Primary IP, Primary Port
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
	
	if(externalAddress)
	{
		predictedPort1 = [externalAddress port];
	}
	else
	{
		DDLogError(@"STUNSocket: Prediction request 1 failed");
		predictedPort1 = 0;
	}
}

- (void)processPredictionResponse2:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Prediction Response 2: \n%@", response);
	
	// Test 2: Primary IP, Secondary Port
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
	
	if(externalAddress)
	{
		predictedPort2 = [externalAddress port];
	}
	else
	{
		DDLogError(@"STUNSocket: Prediction request 2 failed");
		predictedPort2 = 0;
	}
}

- (void)processPredictionResponse3:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Prediction Response 3: \n%@", response);
	
	// Test 3: Secondary IP, Primary Port
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
	
	if(externalAddress)
	{
		predictedPort3 = [externalAddress port];
	}
	else
	{
		DDLogError(@"STUNSocket: Prediction request 3 failed");
		predictedPort3 = 0;
	}
}

- (void)processPredictionResponse4:(STUNMessage *)response
{
	DDLogVerbose(@"STUNSocket: Processing Prediction Response 4: \n%@", response);
	
	// Test 4: Secondary IP, Secondary Port
	
	STUNAddressAttribute *externalAddress = [response xorMappedAddress];
	if(externalAddress == nil)
	{
		externalAddress = [response mappedAddress];
	}
	
	if(externalAddress)
	{
		predictedPort4 = [externalAddress port];
	}
	else
	{
		DDLogError(@"STUNSocket: Prediction request 4 failed");
		predictedPort4 = 0;
	}
}

- (void)processPredictionResponse:(STUNMessage *)response
{
	if(response)
	{
		// Record max round trip time
		NSTimeInterval rtt = [[NSDate date] timeIntervalSinceDate:currentStunMessageFirstSentTime];
		if(rtt > maxRtt)
		{
			maxRtt = rtt;
		}
	}
	
	// Release and nil currentStunMessage variables so multiple responses don't get processed again
	[currentStunMessage release];
	currentStunMessage = nil;
	
	[currentStunMessageDestinationHost release];
	currentStunMessageDestinationHost = nil;
	
	[currentStunMessageFirstSentTime release];
	currentStunMessageFirstSentTime = nil;
	
	switch(currentStunMessageNumber)
	{
		case 101 : [self processPredictionResponse1:response];
		           [self startPredictionRequest2];
			return;
		
		case 102 : [self processPredictionResponse2:response];
		           [self startPredictionRequest3];
			return;
			
		case 103 : [self processPredictionResponse3:response];
		           [self startPredictionRequest4];
			return;
		
		default  : [self processPredictionResponse4:response];
	}
	
	DDLogVerbose(@"STUNSocket: Calculating port prediction");
	
	STUNPortPredictionLogger *ppLogger = [[STUNPortPredictionLogger alloc] initWithLocalPort:[udpSocket localPort]];
	[ppLogger setReportedPort1:predictedPort1];
	[ppLogger setReportedPort2:predictedPort2];
	[ppLogger setReportedPort3:predictedPort3];
	[ppLogger setReportedPort4:predictedPort4];
	[ppLogger autorelease];
	
	// Calculate port prediction.
	// Remember, this step is only performed if our router type has been determined to be symmetric.
	
	int diffA = INT_MIN;
	if((predictedPort1 > 0) && (predictedPort2 > 0))
	{
		diffA = predictedPort2 - predictedPort1;
	}
	
	int diffB = INT_MIN;
	if((predictedPort2 > 0) && (predictedPort3 > 0))
	{
		diffB = predictedPort3 - predictedPort2;
	}
	
	int diffC = INT_MIN;
	if((predictedPort3 > 0) && (predictedPort4 > 0))
	{
		diffC = predictedPort4 - predictedPort3;
	}
	
	// We assume the router assigns port numbers in increasing order unless we discover otherwise
	BOOL portNumbersIncreasing = YES;
	
	UInt16 minPort = 0;
	UInt16 maxPort = 65535;
	
	int predictedPort = 0;
	int maxJump = 0;
	
	if(diffA != INT_MIN)
	{
		// We have diffA - meaning we have predictedPort 1 & 2
		
		if(diffC != INT_MIN)
		{
			// We have diffA - meaning we have predictedPort 1 & 2
			// We have diffC - meaning we have predictedPort 3 & 4
			
			if(diffA == 0 && diffC == 0)
			{
				// The router uses address sensitive mapping.
				// That is, if we use the same internal port,
				// it will assign us the same external port as long as we're sending to the same IP,
				// regardless of which port we're sending to.
				local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
				
				predictedPort = predictedPort3 + diffB;
				
				portNumbersIncreasing = diffB >= 0;
			}
			else if((diffA > 0 && diffB > 0 && diffC > 0) || (diffA < 0 && diffB < 0 && diffC < 0))
			{
				// The router uses port sensitive mapping.
				// Every different external IP and/or port combination we send to gets a new mapping.
				local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
				
				// Furthermore, it appears the router is progressive symmetric
				int avgDiff = (int)ceil((diffA + diffB + diffC) / 3.0);
				predictedPort = predictedPort4 + avgDiff;
				
				portNumbersIncreasing = avgDiff >= 0;
			}
			else
			{
				// The router is likely assigning ports randomly.
				// But at least we know the router is using port sensitive mapping due to diffA and diffC.
				local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
			}
			
			minPort = MIN(MIN(predictedPort1, predictedPort2), MIN(predictedPort3, predictedPort4));
			maxPort = MAX(MAX(predictedPort1, predictedPort2), MAX(predictedPort3, predictedPort4));
			
			maxJump = MAX(ABS(diffA), MAX(ABS(diffB), ABS(diffC)));
		}
		else if(diffB != INT_MIN)
		{
			// We have diffA - meaning we have predictedPort 1 & 2
			// We have diffB - meaning we have predicted port 3
			
			if(diffA == 0)
			{
				// The router uses address sensitive mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
				
				predictedPort = predictedPort3 + diffB;
				
				portNumbersIncreasing = diffB >= 0;
			}
			else
			{
				// The router uses port sensitive mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
				
				int avgDiff = (int)ceil((diffA + diffB) / 2.0);
				predictedPort = predictedPort3 + avgDiff;
				
				portNumbersIncreasing = avgDiff >= 0;
			}
			
			minPort = MIN(MIN(predictedPort1, predictedPort2), predictedPort3);
			maxPort = MAX(MAX(predictedPort1, predictedPort2), predictedPort3);
			
			maxJump = MAX(ABS(diffA), ABS(diffB));
		}
		else if(predictedPort4 > 0)
		{
			// We have diffA - meaning we have predictedPort 1 & 2
			// We have predictedPort 4
			
			int diffE = predictedPort4 - predictedPort2;
			
			if(diffA == 0)
			{
				// The router uses address dependent mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
				
				predictedPort = predictedPort4 + diffE;
				
				portNumbersIncreasing = diffE >= 0;
			}
			else
			{
				// The router uses port sensitive mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
				
				int avgDiff = (int)ceil((diffA + diffE) / 2.0);
				predictedPort = predictedPort4 + avgDiff;
				
				portNumbersIncreasing = avgDiff >= 0;
			}
			
			minPort = MIN(MIN(predictedPort1, predictedPort2), predictedPort4);
			maxPort = MAX(MAX(predictedPort1, predictedPort2), predictedPort4);
			
			maxJump = MAX(ABS(diffA), ABS(diffE));
		}
		else
		{
			// All we have are predicted ports 1 & 2
			
			if(diffA == 0)
			{
				// The router uses address dependent mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
				
				// We'll make an educated guess - the router is progressive
				predictedPort = predictedPort2 + 2;
				
				portNumbersIncreasing = YES;
			}
			else
			{
				// The router uses port sensitive mapping
				local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
				
				predictedPort = predictedPort2 + diffA;
				
				portNumbersIncreasing = diffA >= 0;
			}
			
			minPort = MIN(predictedPort1, predictedPort2);
			maxPort = MAX(predictedPort1, predictedPort2);
			
			maxJump = ABS(diffA);
		}
	}
	else
	{
		// We DON'T have diffA - meaning we're MISSING predictedPort 1 or 2 (or both)
		
		if(diffC != INT_MIN)
		{
			// We have diffC - meaning we have predictedPort 3 & 4
			
			if(diffB != INT_MIN)
			{
				// We have diffC - meaning we have predictedPort 3 & 4
				// We have diffB - meaning we have predicted port 2
				
				if(diffC == 0)
				{
					// The router uses address dependent mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
					
					predictedPort = predictedPort4 + diffB;
					
					portNumbersIncreasing = diffB >= 0;
				}
				else
				{
					// The router uses port sensitive mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
					
					int avgDiff = (int)ceil((diffB + diffC) / 2.0);
					predictedPort = predictedPort4 + avgDiff;
					
					portNumbersIncreasing = avgDiff >= 0;
				}
				
				minPort = MIN(predictedPort2, MIN(predictedPort3, predictedPort4));
				maxPort = MAX(predictedPort2, MAX(predictedPort3, predictedPort4));
				
				maxJump = MAX(ABS(diffB), ABS(diffC));
			}
			else if(predictedPort1 > 0)
			{
				// We have diffC - meaning we have predictedPort 3 & 4
				// We have predictedPort 1
				
				int diffD = predictedPort3 - predictedPort1;
				
				if(diffC == 0)
				{
					// The router uses address dependent mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
					
					predictedPort = predictedPort4 + diffD;
					
					portNumbersIncreasing = diffD >= 0;
				}
				else
				{
					// The router uses port sensitive mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
					
					int avgDiff = (int)ceil((diffA + diffD) / 2.0);
					predictedPort = predictedPort4 + avgDiff;
					
					portNumbersIncreasing = avgDiff >= 0;
				}
				
				minPort = MIN(predictedPort1, MIN(predictedPort3, predictedPort4));
				maxPort = MAX(predictedPort1, MAX(predictedPort3, predictedPort4));
				
				maxJump = MAX(ABS(diffC), ABS(diffD));
			}
			else
			{
				// All we have are predicted ports 3 & 4
				
				if(diffC == 0)
				{
					// The router uses address sensitive mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_ADDRESS;
					
					// We'll make an educated guess - the router is progressive
					predictedPort = predictedPort4 + 2;
					
					portNumbersIncreasing = YES;
				}
				else
				{
					// The router uses port sensitive mapping
					local_portAllocationType = PORT_ALLOCATION_TYPE_PORT;
					
					predictedPort = predictedPort4 + diffC;
					
					portNumbersIncreasing = diffC >= 0;
				}
				
				minPort = MIN(predictedPort3, predictedPort4);
				maxPort = MAX(predictedPort3, predictedPort4);
				
				maxJump = ABS(diffC);
			}
		}
		else if(diffB != INT_MIN)
		{
			// All we have ar predicted ports 2 & 3
			// Since these came from different address, we don't know the router allocation type
			local_portAllocationType = PORT_ALLOCATION_TYPE_UNKNOWN;
			
			if(diffB == 0)
			{
				// We'll make an educated guess - the router is progressive
				predictedPort = predictedPort3 + 2;
				
				portNumbersIncreasing = YES;
			}
			else
			{
				predictedPort = predictedPort3 + diffB;
				
				portNumbersIncreasing = diffB >= 0;
			}
			
			minPort = MIN(predictedPort2, predictedPort3);
			maxPort = MAX(predictedPort2, predictedPort3);
			
			maxJump = ABS(diffB);
		}
		else
		{
			// We DON'T have diffA - meaning we're MISSING predictedPort 1 or 2 (or both)
			// We DON'T have diffB - meaning we're MISSING predictedPort 2 or 3 (or both)
			// We DON'T have diffC - meaning we're MISSING predictedPort 3 or 4 (or both)
			
			local_portAllocationType = PORT_ALLOCATION_TYPE_UNKNOWN;
			
			if((predictedPort1 > 0) && (predictedPort3 > 0))
			{
				int diffD = predictedPort3 - predictedPort1;
				predictedPort = predictedPort3 + diffD;
				
				portNumbersIncreasing = diffD >= 0;
				minPort = MIN(predictedPort1, predictedPort3);
				maxPort = MAX(predictedPort1, predictedPort3);
				maxJump = ABS(diffD);
			}
			else if((predictedPort2 > 0) && (predictedPort4 > 0))
			{
				int diffE = predictedPort4 - predictedPort2;
				predictedPort = predictedPort4 + diffE;
				
				portNumbersIncreasing = diffE >= 0;
				minPort = MIN(predictedPort2, predictedPort4);
				maxPort = MAX(predictedPort2, predictedPort4);
				maxJump = ABS(diffE);
			}
			else if((predictedPort1 > 0) && (predictedPort4 > 0))
			{
				int diffF = predictedPort4 - predictedPort1;
				predictedPort = predictedPort4 + diffF;
				
				portNumbersIncreasing = diffF >= 0;
				minPort = MIN(predictedPort1, predictedPort4);
				maxPort = MAX(predictedPort1, predictedPort4);
				maxJump = ABS(diffF);
			}
		}
	}
	
	// Done with the giant IF statement
	
	DDLogVerbose(@"STUNSocket: predictedPort: %i", predictedPort);
	
	if(predictedPort < 1024 || predictedPort > 65535)
	{
		// We have no clue what's coming next
		local_externalPort = [STUNUtilities randomPortNumber];
	}
	else
	{
		local_externalPort = predictedPort;
	}
	
	DDLogVerbose(@"STUNSocket: local_externalPort: %hu", local_externalPort);
	
	if((local_routerType >= ROUTER_TYPE_SYMMETRIC_FULL) && (remote_routerType >= ROUTER_TYPE_SYMMETRIC_FULL))
	{
		// We're going to be firing off several sockets,
		// so we may want to give ourselves a little more breathing room.
		if(portNumbersIncreasing)
		{
			if(local_externalPort <= 65533)
			{
				if(maxJump <= 2) local_externalPort += 2;
			}
		}
		else
		{
			if(local_externalPort >= 1026)
			{
				if(maxJump <= 2) local_externalPort -= 2;
			}
		}
		
		DDLogVerbose(@"STUNSocket: local_externalPort after delta: %hu", local_externalPort);
		
		[ppLogger setPredictedPort:local_externalPort];
		[logger addPortPredictionLogger:ppLogger];
		
		// Send our port prediction in a callback message
		[self sendCallbackMessage];
		
		// If we've already received their port prediction
		if(remote_externalPort > 0)
		{
			// We're ready to start PS-STUN algorithm 2
			[self startPS2Validation];
		}
	}
	else
	{
		// We're behind a symmetric router, but the remote host is behind a port restricted cone router.
		// We need to calculate a range for the remote host to send packets to.
		// As long as our mapped port resides within this range, the traversal should work.
		
		if(portNumbersIncreasing)
		{
			if((maxPort < local_externalPort) && ((local_externalPort - maxPort) <= 9))
			{
				local_externalPortRange = NSMakeRange(maxPort + 1, 20);
			}
			else
			{
				local_externalPortRange = NSMakeRange(local_externalPort - 9, 20);
			}
			
			while(NSLocationInRange(65536, local_externalPortRange))
			{
				local_externalPortRange.location = local_externalPortRange.location - 1;
			}
		}
		else
		{
			// Note: local_externalPort is guaranteed to be >= 1024
			
			if((minPort > local_externalPort) && ((minPort - local_externalPort) <= 9))
			{
				local_externalPortRange = NSMakeRange(minPort - 20, 20);
			}
			else
			{
				local_externalPortRange = NSMakeRange(local_externalPort - 10, 20);
			}
			
			while(NSLocationInRange(1023, local_externalPortRange))
			{
				local_externalPortRange.location = local_externalPortRange.location + 1;
			}
		}
		
		DDLogVerbose(@"STUNSocket: local_externalPortRange: %@", NSStringFromRange(local_externalPortRange));
		
		[ppLogger setPredictedPort:local_externalPort];
		[ppLogger setPredictedPortRange:local_externalPortRange];
		[logger addPortPredictionLogger:ppLogger];
		
		if(isClient)
			[self sendCallbackMessage];
		else
		{
			if(attemptCount == 0)
				[self sendAcceptMessage];
			else
				[self sendCallbackMessage];
		}
		
		// Note: The sendAcceptMessage method will update state to STATE_ACCEPT_SENT
		
		[self startPS1Validation];
		
		// Note: The startPs1Validation method will update state to STATE_VALIDATION_PS1
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncUdpSocket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when the datagram with the given tag has been sent.
**/
- (void)onUdpSocket:(AsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
	DDLogVerbose(@"STUNSocket: onUdpSocket:%p didSendDataWithTag:%d", sock, tag);
	
	// Note:
	// tag 0 = standard validation
	// tag 1 - 6 = discovery binding requests
	// tag 101 - 104 = prediction binding requests
	// tag 200 - 299 = PS-STUN 1 probes
	// tag 300 - 399 = PS-STUN 1 validation
	// tag 400 - 499 = PS-STUN 2 probes
	// tag 500 - 599 = PS-STUN 2 validation
}

/**
 * Called if an error occurs while trying to send a datagram.
 * This could be due to a timeout, or something more serious such as the data being too large to fit in a sigle packet.
**/
- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
	DDLogVerbose(@"STUNSocket: onUdpSocket:%p didNotSendDataWithTag:%d dueToError:%@", sock, tag, error);
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:@"error=%@", error];
	
	// Note:
	// tag 0 = standard validation
	// tag 1 - 6 = discovery binding requests
	// tag 101 - 104 = prediction binding requests
	// tag 200 - 299 = PS-STUN 1 probes
	// tag 300 - 399 = PS-STUN 1 validation
	// tag 400 - 499 = PS-STUN 2 probes
	// tag 500 - 599 = PS-STUN 2 validation
}

/**
 * Called when the socket has received the requested datagram.
 * Return NO to ignore the data, and continue with receive as if it never arrived.
**/
- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock
	 didReceiveData:(NSData *)data
			withTag:(long)tag 
		   fromHost:(NSString *)host
			   port:(UInt16)port
{
	if(state == STATE_START || state == STATE_PORT_PREDICTION)
	{
		STUNMessage *response = [STUNMessage parseMessage:data];
		
		if(response == nil)
		{
			// Data wasn't a proper binding response
			return NO;
		}
		
		if(![[currentStunMessage transactionID] isEqualToData:[response transactionID]])
		{
			// Data wasn't a response to our most recent binding request
			// Could be a delayed response from an earlier transmission
			return NO;
		}
		
		if(state == STATE_START)
			[self processDiscoveryResponse:response];
		else
			[self processPredictionResponse:response];
		
		return YES;
	}
	else if(state == STATE_VALIDATION_STD || state == STATE_VALIDATION_PS1 || state == STATE_VALIDATION_PS2)
	{
		// Ignore the packet if we've already received a validation message.
		// This may happen because of retransmissions, or due to the multiple sockets used in the PS-STUN techniques.
		if(readValidationComplete) return NO;
		
		// All MD5 hashes are 128 bits = 16 bytes
		if([data length] != 16)
		{
			if(!isClient && state == STATE_VALIDATION_PS2)
			{
				// The server may have received a probe from the client.
				// If so, it should immediately reply to the probe with a validation packet.
				
				NSData *probeData = [PROBE_PS2 dataUsingEncoding:NSUTF8StringEncoding];
				
				if([data length] == [probeData length])
				{
					DDLogVerbose(@"STUNSocket: Responding to received probe...");
					
					[sock sendData:validationData toHost:host port:port withTimeout:NO_TIMEOUT tag:599];
				}
			}
			
			return NO;
		}
		
		// Check the received data, and make sure it's correct.
		// It should be:
		// MD5(sender.jid.bare + uuid)
		
		NSString *hashMe = [NSString stringWithFormat:@"%@%@", [jid bare], uuid];
		
		NSData *compareMe = [[hashMe dataUsingEncoding:NSUTF8StringEncoding] md5Digest];
		
		if([compareMe isEqualToData:data])
		{
			// The received validation message is confirmed
			readValidationComplete = YES;
			
			// Inform the remote host that we've received their validation message
			[self sendValidatedMessage];
			
			// Check to see if we're done
			if(readValidationComplete && writeValidationComplete)
			{
				// If PS-STUN-1 was used, then side A opened up 4 sockets, and fired probes to punch
				// holes in its rotuer.  While side B went through a predicted port range, and fired
				// validation packets.  When side A received the validation packets, it reported the validation,
				// and proceeded to start firing its own validation packets.  Side B does not start listening
				// for validation until after it has received the XMPP validated message.  Side B does not yet
				// know which port was successful.
				// Only side B will arrive at this point.
				
				// If PS-STUN-2 was used, then both sides were firing at the other side's predicted port.
				// The client was initially firing probes, while the server was firing validation packets.
				// If the server ever received a probe, it immediately responded with a validation packet.
				// Eventually the client received the validation, reported it, and responded with its own validation.
				// The server does not yet know which port was successful.  Remember, the server may
				// have replied to a probe on a port other than the client's initial predicted port.  Which is good
				// because it allows us to take advantage of "Symmetric - Full/Restricted" routers.
				// It is technically possible for either the client or server to arrive at this point,
				// but it is most likely the server.
				
				// Update variables
				[remote_externalIP release];
				remote_externalIP = [host copy];
				remote_externalPort = port;
				
				// And we're done!
				[self succeedWithSocket:sock host:host port:port];
			}
			else
			{
				if(state == STATE_VALIDATION_STD)
				{
					// If our router type was None or Full Cone, we don't know the remote IP yet.
					// If the remote router was symmetric, the port number may have changed.
					if(![remote_externalIP isEqualToString:host] || remote_externalPort != port)
					{
						// Update variables
						[remote_externalIP release];
						remote_externalIP = [host copy];
						remote_externalPort = port;
						
						// We either need to start outgoing validation for the first time,
						// or we've been sending to the wrong IP and/or port, and we need to restart.
						[self restartOutgoingValidation];
					}
					else
					{
						// Just in case their network is going slow, or the XMPP server is overloaded,
						// we restartOutgoingValidation because it's very unlikely to fail at this point.
						[self restartOutgoingValidation];
					}
				}
				else if(state == STATE_VALIDATION_PS1)
				{
					// Only the side with the symmetric NAT will arrive at this point.
					// This is because only this side is listening on its udp sockets.
					// In addition to this, the symmetric side hasn't started sending validation data yet.
					// It has only sent out probe data to open up multiple holes in its router.
					
					// We had opened multiple holes in the router, and the remote host found one of them.
					// Using the successful socket, we're ready to start our outgoing validation.
					
					// Extract the successful socket
					udpSocket = [sock retain];
					
					// The remote IP and port should theoretically be the same as originally reported,
					// but we'll save them just in case the router has decided to behave differently.
					[remote_externalIP release];
					remote_externalIP = [host copy];
					remote_externalPort = port;
					
					// Switch to normal validation
					state = STATE_VALIDATION_STD;
					
					// We have not started outgoing validation yet - it's time to start
					[self restartOutgoingValidation];
				}
				else
				{
					// It's possible for the client or server to arrive at this point.
					
					// Client:
					// We had opened several sockets, and started sending probes and receiving on all of them.
					// We can stop sending probes, and start sending validation on the successful socket.
					
					// Server:
					// We had opened several sockets, and started sending validation and receiving on all of them.
					// It seems that the client received our validation, and we've received their validation
					// response prior to receiving their xmpp VALIDATED message.
					// The result is pretty much the same as for the client though.
					// We should be able to stop sending validation on all sockets except the successful socket.
					
					// Extract the successful socket
					udpSocket = [sock retain];
					
					// The remote IP and port should theoretically be the same as their predicted port,
					// but we'll save them just in case the router has decided to behave differently.
					[remote_externalIP release];
					remote_externalIP = [host copy];
					remote_externalPort = port;
					
					// Switch to normal validation
					state = STATE_VALIDATION_STD;
					
					// If we're the client, we have not started outgoing validation yet - it's time to start
					[self restartOutgoingValidation];
				}
			}
			
			return YES;
		}
		else
		{
			readValidationFailed = YES;
		}
		
		return NO;
	}
	
	// This is likely duplicate binding responses as a result of binding request retransmissions,
	// or duplicate validation messages as a result of validation retransmissions.
	return NO;
}

/**
 * Called if an error occurs while trying to receive a requested datagram.
 * This is generally due to a timeout, but could potentially be something else if some kind of OS error occurred.
**/
- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotReceiveDataWithTag:(long)tag dueToError:(NSError *)error
{
	if(state == STATE_START || state == STATE_PORT_PREDICTION)
	{
		[self maybeResendCurrentStunMessage];
	}
	else if(state == STATE_VALIDATION_STD || state == STATE_VALIDATION_PS1 || state == STATE_VALIDATION_PS2)
	{
		if(readValidationComplete)
		{
			// One of the multiple sockets failed to receive validation.
			// But this doesn't matter because one of the other ones did.
			return;
		}
		
		if(restartIncomingValidationDate)
		{
			NSTimeInterval remaining = STD_VALIDATION_TIMEOUT + [restartIncomingValidationDate timeIntervalSinceNow];
			
			if((remaining > 0) && (remaining < STD_VALIDATION_TIMEOUT))
			{
				DDLogVerbose(@"STUNSocket: Restarting incoming validation: %d", remaining);
				
				// Continue waiting for data on the given socket
				// This socket is either udpSocket, or one of the many created sockets in the PS-STUN algorithms
				[sock receiveWithTimeout:remaining tag:0];
				
				// Note: Do not release the startIncomingValidationDate here.
				// In the PS2 algorithm, there are multiple sockets, and
				// they ALL need to be restarted after they time out.
				// The restart process won't continue forever because the
				// second time around the remaining time interval will fall below zero.
				
				return;
			}
		}
		
		// For PS-STUN 1 - The symmetric side decides when to reset
		// For PS-STUN 2 - The client side decides when to reset
		
		BOOL myDecision = NO;
		if(state == STATE_VALIDATION_PS1)
		{
			myDecision = local_routerType >= ROUTER_TYPE_SYMMETRIC_FULL;
		}
		else if(state == STATE_VALIDATION_PS2)
		{
			myDecision = isClient;
		}
		
		if(myDecision)
		{
			if(++attemptCount < MAX_ATTEMPTS)
			{
				// Port prediction didn't work, let's try it again
				
				// Notify the other side
				[self sendResetMessage];
				
				// Stop sending probe messages (PS2)
				[validationTimer invalidate];
				[validationTimer release];
				validationTimer = nil;
				
				// Dump the scanning sockets
				uint i;
				for(i = 0; i < [scanningSockets count]; i++)
				{
					AsyncUdpSocket *socket = [scanningSockets objectAtIndex:i];
					
					[socket setDelegate:nil];
					[socket close];
				}
				[scanningSockets autorelease]; // Don't release sockets within delegate callback
				scanningSockets = nil;
				
				// And start port prediction again
				[self startPortPrediction];
			}
			else
			{
				// Port prediction didn't work several times in a row - time to give up
				[self sendFailMessage];
				
				[logger setFailureReason:@"Exceeded max number of attempts"];
				[self fail];
			}
		}
		else
		{
			DDLogError(@"STUNSocket: Never received validation");
			
			[logger setFailureReason:@"Never received validation"];
			[self fail];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Validation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setupValidationData
{
	if(validationData == nil)
	{
		// Validation message should be of the form:
		// MD5(myJid.Bare + uuid)
		
		NSString *bareJID = [[[MojoXMPPClient sharedInstance] myJID] bare];
		
		NSString *hashMe = [NSString stringWithFormat:@"%@%@", bareJID, uuid];
		
		validationData = [[[hashMe dataUsingEncoding:NSUTF8StringEncoding] md5Digest] retain];
	}
}

/**
 * Starts the validation process.
 * A validation message is sent, with a retransmission scheme similar to that defined in the STUN RFC.
 * The validation message is retransmitted until we receive, via xmpp, a validation receipt, or until we time out.
**/
- (void)startValidation
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Update state
	state = STATE_VALIDATION_STD;
	
	// We can't start sending our validation until we know the remote host's IP address.
	// If our router type is None or Full Cone, then we'll have to wait until after we've received their validation.
	if(remote_externalIP)
	{
		DDLogVerbose(@"STUNSocket: Starting outgoing validation...");
		[logger addTraceMessage:@"outgoing"];
		
		[self setupValidationData];
		
		[udpSocket sendData:validationData
					 toHost:remote_externalIP
					   port:remote_externalPort
				withTimeout:NO_TIMEOUT
						tag:0];
		
		validationElapsed = 0.0;
		validationTimeout = 0.1;
		validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
															target:self
														  selector:@selector(doValidationTimeout:)
														  userInfo:nil
														   repeats:NO] retain];
	}
	
	// Start reading the validation message from the remote client
	DDLogVerbose(@"STUNSocket: Starting incoming validation...");
	[logger addTraceMessage:@"incoming"];
	
	[udpSocket receiveWithTimeout:STD_VALIDATION_TIMEOUT tag:0];
}

/**
 * Incoming validation is restarted when we receive a VALIDATED message.
 * This is done because the remote host may have only just discovered our mapped external port.
**/
- (void)restartIncomingValidation
{
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// This method is called from xmppClient:didReceiveMessage: after receiving a validated message.
	// Thus:
	// writeValidationComplete == YES
	// readValidationComplete  == NO
	
	if(state == STATE_VALIDATION_STD)
	{
		// We can't actually stop the queued receive operation since it's already in progress.
		// But this is no problem, we'll simply restart the validation if it fails.
		// And we record the current time to make sure we don't wait overly long for the validation to complete.
		restartIncomingValidationDate = [[NSDate date] retain];
	}
	else if(state == STATE_VALIDATION_PS1)
	{
		// Only the non-symmetric side will arrive at this point.
		// We haven't started incoming validation yet.
		
		DDLogVerbose(@"STUNSocket: Starting incoming validation for PS1...");
		
		// Switching back to regular validation techniques
		state = STATE_VALIDATION_STD;
		
		[udpSocket receiveWithTimeout:STD_VALIDATION_TIMEOUT tag:0];
	}
	else if(state == STATE_VALIDATION_PS2)
	{
		// It is technically possible for either the client or server to arrive at this point,
		// but is is most likely the server.
		// All sockets, either on client or server, are already receiving data.
		
		DDLogVerbose(@"STUNSocket: Starting/Restarting incoming validation for PS2...");
		
		// Switching back to regular validation techniques
		state = STATE_VALIDATION_STD;
		
		restartIncomingValidationDate = [[NSDate date] retain];
	}
}

/**
 * Starts or restarts the standard outgoing validation.
**/
- (void)restartOutgoingValidation
{
	NSAssert((state == STATE_VALIDATION_STD), @"Inappropriate validation type");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	if(validationTimer)
	{
		[validationTimer invalidate];
		[validationTimer release];
		validationTimer = nil;
		
		DDLogVerbose(@"STUNSocket: Restarting outgoing validation...");
	}
	else
	{
		DDLogVerbose(@"STUNSocket: Starting outgoing validation...");
	}
	
	[self setupValidationData];
	
	[udpSocket sendData:validationData
				 toHost:remote_externalIP
				   port:remote_externalPort
			withTimeout:NO_TIMEOUT
					tag:0];
	
	validationElapsed = 0.0;
	validationTimeout = 0.1;
	validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
														target:self
													  selector:@selector(doValidationTimeout:)
													  userInfo:nil
													   repeats:NO] retain];
}

/**
 * This type of validation is used if one router is port restricted cone and the other is symmetric.
 * The symmetric host sends a range of port predictions, and the other host fires at every port in the range.
**/
- (void)startPS1Validation
{
	DDLogVerbose(@"STUNSocket: Starting PS1 Validation...");
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Update state
	state = STATE_VALIDATION_PS1;
	
	[logger setTraversalAlgorithm:TRAVERSAL_ALGORITHM_PSSTUN1];
	
	// The PS-STUN algorithm was introduced in the paper "Research on Symmetric NAT Traversal in P2P applications"
	// This is the first technique introduced in the paper, which applies to "class A and B"
	// That is, one router is symmetric and the other is port restricted cone
	// We use this concept, and make multiple holes in the symmetric NAT in step 2
	
	if(local_routerType >= ROUTER_TYPE_SYMMETRIC_FULL)
	{
		// We're going to fire probes from multiple internal sockets.
		// This will create multiple external mappings, thus increasing the chances of traversal.
		// Remember, even if our router uses address sensitive mapping, we'll still get separate mappings since
		// we're sending from different internal ports.
		
		// Create scanning sockets array
		scanningSockets = [[NSMutableArray alloc] initWithCapacity:4];
		
		// Move the existing udp socket (created in startPortPrediction) into the array
		[scanningSockets addObject:udpSocket];
		[udpSocket release];
		udpSocket = nil;
		
		// Fill the rest of the array with new sockets
		int i;
		for(i = 1; i < 4; i++)
		{
			AsyncUdpSocket *sock = [[AsyncUdpSocket alloc] initIPv4];
			[sock setDelegate:self];
			[sock setMaxReceiveBufferSize:256];
			
			[scanningSockets addObject:sock];
			
			[sock release];
		}
		
		// We're going to be listening on all the scanning sockets - any one of them may succeed.
		// When one does, it will be stored in the udpSocket variable.
		
		// We don't send the validation data yet - just a probe.
		NSData *probeData = [PROBE_PS1 dataUsingEncoding:NSUTF8StringEncoding];
		
		// Note: probeData should never be 16 bytes, as that would make it the same size as validation data.
		// The length of the probe data above is only 15 bytes.
		
		// Now send the probe data on each socket.
		// Each socket will create a seperate mapping in the router.
		// And then start waiting for validation messages on each socket.
		for(i = 0; i < [scanningSockets count]; i++)
		{
			DDLogVerbose(@"STUNSocket: Sending probe from socket index %i", i);
			
			AsyncUdpSocket *scanningSocket = [scanningSockets objectAtIndex:i];
			
			[scanningSocket sendData:probeData
							  toHost:remote_externalIP
								port:remote_externalPort
						 withTimeout:NO_TIMEOUT
								 tag:(200+i)];
			
			DDLogVerbose(@"STUNSocket: Receiving on socket index %i", i);
			
			[scanningSocket receiveWithTimeout:PS1_VALIDATION_TIMEOUT tag:(300+i)];
		}
	}
	else
	{
		// We're going to scan through the port range given to us (starting with the predicted port)
		
		[self setupValidationData];
		
		DDLogVerbose(@"STUNSocket: Sending validation to port %hu", remote_externalPort);
		
		[udpSocket sendData:validationData
					 toHost:remote_externalIP
					   port:remote_externalPort
				withTimeout:NO_TIMEOUT
						tag:300];
		
		validationElapsed = 0.0;
		validationTimeout = 0.1;
		validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
															target:self
														  selector:@selector(doPS1ValidationTimeout:)
														  userInfo:[NSNumber numberWithUnsignedInt:0]
														   repeats:NO] retain];
		
		// We don't bother trying to receive the validation until we've received a validated receipt
	}
}

/**
 * This type of validation is used if both routers are symmetric.
 * Both hosts send a port prediction to the other.
 * Then both hosts use a series of internal ports, and attempt to connect to the other host's predicted port.
**/
- (void)startPS2Validation
{
	DDLogVerbose(@"STUNSocket: Starting PS2 Validation...");
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	
	// Update state
	state = STATE_VALIDATION_PS2;
	
	[logger setTraversalAlgorithm:TRAVERSAL_ALGORITHM_PSSTUN2];
	
	// The PS-STUN algorithm was introduced in the paper "Research on Symmetric NAT Traversal in P2P applications".
	// This is the second technique introduced in the paper, which applies to "class C".
	// We actually apply it to classes D & E as well, since there are no other known techniques that apply.
	// In other words, both routers are symmetric.
	
	// Discussion:
	// This technique will have varying degrees of success based on the types of symmetric routers.
	// For example, if one of the routers is SYMMETRIC_FULL or SYMMETRIC_RESTRICTED, and that host manages
	// to get it's port prediction correct, then it doesn't matter what ports the other host is assigned, as
	// the router will allow all incoming packets from the other host.
	// However, if both routers are SYMMETRIC_PORT_RESTRICTED then both hosts will have to get their predictions right.
	// This is because all packets are going to the other's predicted port, and neither router will let any packets
	// through except those coming from the predicted port.
	
	// Create scanning sockets array
	scanningSockets = [[NSMutableArray alloc] initWithCapacity:NUM_PS2_SOCKETS];
	
	// Move the existing udp socket (created in startPortPrediction) into the array
	[scanningSockets addObject:udpSocket];
	[udpSocket release];
	udpSocket = nil;
	
	// We're not going to create all the other 19 sockets right now.
	// Instead, we'll create them as we get to them.
	// This way, if the port predictions are accurate, we won't waste RAM and CPU with sockets we never use.
		
	// Setup validation data
	[self setupValidationData];
	
	// We're going to be sending the validation data from every socket.
	// Each socket will create a seperate mapping in the router.
	// But we don't want to flood the router by sending from all of them all at once.
	// So we'll be using the timer to wait for a bit in between each socket.
	
	AsyncUdpSocket *sock = [scanningSockets objectAtIndex:0];
	
	// Only the server sends validation now.
	// The client will instead send probes to help prevent a race condition.
	if(isClient)
	{
		DDLogVerbose(@"STUNSocket: Sending probe from socket index 0");
		
		// We don't send the validation data yet - just a probe.
		NSData *probeData = [PROBE_PS2 dataUsingEncoding:NSUTF8StringEncoding];
		
		// Note: probeData should never be 16 bytes, as that would make it the same size as validation data.
		// The length of the probe data above is only 15 bytes.
		
		[sock sendData:probeData
				toHost:remote_externalIP
				  port:remote_externalPort
		   withTimeout:NO_TIMEOUT
				   tag:400];
	}
	else
	{
		DDLogVerbose(@"STUNSocket: Sending validation from socket index 0");
		
		[sock sendData:validationData
				toHost:remote_externalIP
				  port:remote_externalPort
		   withTimeout:NO_TIMEOUT
				   tag:500];
	}
	
	validationElapsed = 0.0;
	validationTimeout = 0.1;
	validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
														target:self
													  selector:@selector(doPS2ValidationTimeout:)
													  userInfo:[NSNumber numberWithUnsignedInt:0]
													   repeats:NO] retain];
	
	DDLogVerbose(@"STUNSocket: Receiving on socket index 0");
	
	if(isClient)
	{
		// The client listens for incoming validation data
		[sock receiveWithTimeout:PS2_VALIDATION_CLIENT_TIMEOUT tag:500];
	}
	else
	{
		// The server must listen for probes, and respond to any probes it may receive with a validation reply
		[sock receiveWithTimeout:PS2_VALIDATION_SERVER_TIMEOUT tag:500];
	}
}

/**
 * Handles retransmissions of a standard validation message, incrementing the timeout as needed,
 * and failing if max timeout is reached.
**/
- (void)maybeResendValidation
{
	NSAssert((state == STATE_VALIDATION_STD), @"Inappropriate validation type");
	
	// Send time:   0ms > 100ms > 300ms >  700ms > 1500ms > 3100ms > 4700ms > 6300ms
	// Wait time: 100ms > 200ms > 400ms >  800ms > 1600ms > 1600ms > 1600ms > 1600ms
	// Elapsed  : 100ms > 300ms > 700ms > 1500ms > 3100ms > 4700ms > 6300ms > 7900ms
	
	validationElapsed += validationTimeout;
	if(validationTimeout < 1.6)
	{
		validationTimeout = validationTimeout * 2.0;
	}
	
	if(validationElapsed < 7.9)
	{
		DDLogVerbose(@"STUNSocket: Resending validation");
		
		// Resend validation data
		[udpSocket sendData:validationData
					 toHost:remote_externalIP
					   port:remote_externalPort
				withTimeout:NO_TIMEOUT
						tag:0];
		
		
		// Restart validation timer
		[validationTimer release];
		validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
															target:self
														  selector:@selector(doValidationTimeout:)
														  userInfo:nil
														   repeats:NO] retain];
	}
	else
	{
		DDLogVerbose(@"STUNSocket: Never received validation receipt (STD)");
		
		[logger setFailureReason:@"Never received validation receipt (STD)"];
		[self fail];
	}
}

/**
 * Handles sending the next validation packet in the PS-STUN 1 algorithm.
 * With this technique, we loop through the given port range, sending to each port.
**/
- (void)maybeSendNextPS1Validation
{
	NSAssert((state == STATE_VALIDATION_PS1), @"Inappropriate validation type");
	
	// The first time through the range we fire every 100 milliseconds
	// After that, we fire every 200 milliseconds
	// After that, we fire every 400 milliseconds before timing out
	// 
	// Total = 2 + 4 + 8 = 14 seconds
	
	validationElapsed += validationTimeout;
	
	unsigned int currentPortIndex = [[validationTimer userInfo] unsignedIntValue] + 1;
	
	BOOL timedOut = NO;
	
	if(currentPortIndex >= remote_externalPortRange.length)
	{
		currentPortIndex = 0;
		
		if(validationTimeout == 0.1) {
			validationTimeout = 0.2;
		}
		else if(validationTimeout == 0.2) {
			validationTimeout = 0.4;
		}
		else {
			timedOut = YES;
		}
	}
	
	if(!timedOut)
	{
		UInt16 currentPort = [self getPort:currentPortIndex
								 fromRange:remote_externalPortRange
						 withPredictedPort:remote_externalPort];
		
		DDLogVerbose(@"STUNSocket: Sending validation to port %hu", currentPort);
		
		[udpSocket sendData:validationData
					 toHost:remote_externalIP
					   port:currentPort
				withTimeout:NO_TIMEOUT
						tag:(300+currentPortIndex)];
		
		// Restart validation timer
		[validationTimer release];
		validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
															target:self
														  selector:@selector(doPS1ValidationTimeout:)
														  userInfo:[NSNumber numberWithUnsignedInt:currentPortIndex]
														   repeats:NO] retain];
	}
	else
	{
		DDLogError(@"STUNSocket: Never received validation receipt (PS1)");
		
		[logger setFailureReason:@"Never received validation receipt (PS1)"];
		[self fail];
	}
}

- (void)maybeSendNextPS2Validation
{
	// The first time through the sockets we fire every 100 milliseconds
	// After that, we fire every 200 milliseconds
	// After that, we fire every 400 milliseconds before timing out
	
	validationElapsed += validationTimeout;
	
	unsigned int currentPortIndex = [[validationTimer userInfo] unsignedIntValue] + 1;
	
	BOOL timedOut = NO;
	
	if(currentPortIndex >= NUM_PS2_SOCKETS)
	{
		currentPortIndex = 0;
		
		if(validationTimeout == 0.1) {
			validationTimeout = 0.2;
		}
		else if(validationTimeout == 0.2) {
			validationTimeout = 0.4;
		}
		else {
			timedOut = YES;
		}
	}
	else if(validationTimeout == 0.1)
	{
		// First time through the list of sockets.
		// We're creating them as we need them to potentially save resources.
		
		AsyncUdpSocket *newSocket = [[AsyncUdpSocket alloc] initIPv4];
		[newSocket setDelegate:self];
		[newSocket setMaxReceiveBufferSize:256];
		
		[scanningSockets addObject:newSocket];
		
		[newSocket release];
	}
	
	if(!timedOut)
	{
		AsyncUdpSocket *sock = [scanningSockets objectAtIndex:currentPortIndex];
		
		if(isClient)
		{
			DDLogVerbose(@"STUNSocket: Sending probe from socket index %u", currentPortIndex);
			
			// The client sends probes until it receives a validation packet
			NSData *probeData = [PROBE_PS2 dataUsingEncoding:NSUTF8StringEncoding];
			
			[sock sendData:probeData
					toHost:remote_externalIP
					  port:remote_externalPort
			   withTimeout:NO_TIMEOUT
					   tag:(400+currentPortIndex)];
		}
		else
		{
			DDLogVerbose(@"STUNSocket: Sending validation from socket index %u", currentPortIndex);
			
			[sock sendData:validationData
					toHost:remote_externalIP
					  port:remote_externalPort
			   withTimeout:NO_TIMEOUT
					   tag:(500+currentPortIndex)];
		}
		
		// Restart validation timer
		[validationTimer release];
		validationTimer = [[NSTimer scheduledTimerWithTimeInterval:validationTimeout
															target:self
														  selector:@selector(doPS2ValidationTimeout:)
														  userInfo:[NSNumber numberWithUnsignedInt:currentPortIndex]
														   repeats:NO] retain];
		
		// If we just created this socket (meaning it has no queued receive operations)
		if(validationTimeout == 0.1)
		{
			DDLogVerbose(@"STUNSocket: Receiving on socket index %u", currentPortIndex);
			
			if(isClient)
			{
				// The client is listening for validation
				[sock receiveWithTimeout:PS2_VALIDATION_CLIENT_TIMEOUT tag:(500+currentPortIndex)];
			}
			else
			{
				// The server must listening for probes
				[sock receiveWithTimeout:PS2_VALIDATION_SERVER_TIMEOUT tag:(500+currentPortIndex)];
			}
		}
	}
	else
	{
		DDLogError(@"STUNSocket: Never received validation receipt (PS2)");
		
		[logger setFailureReason:@"Never received validation receipt (PS2)"];
		[self fail];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Timeouts
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Note: The validationTimer is destroyed when we get our validation receipt.

- (void)doValidationTimeout:(NSTimer *)aTimer
{
	if(state == STATE_VALIDATION_STD)
	{
		[self maybeResendValidation];
	}
}

- (void)doPS1ValidationTimeout:(NSTimer *)aTimer
{
	if(state == STATE_VALIDATION_PS1)
	{
		[self maybeSendNextPS1Validation];
	}
}

- (void)doPS2ValidationTimeout:(NSTimer *)aTimer
{
	if(state == STATE_VALIDATION_PS2)
	{
		[self maybeSendNextPS2Validation];
	}
}

- (void)doTotalTimeout:(NSTimer *)aTimer
{
	if(state != STATE_DONE && state != STATE_FAILURE)
	{
		DDLogVerbose(@"STUNSocket: doTotalTimeout:");
		[logger addTraceMethod:NSStringFromSelector(_cmd)];
		[logger addTraceMessage:StringFromState(state)];
		
		// A timeout occured to cancel the entire STUN procedure.
		// This probably means the other endpoint crashed, or a network error occurred.
		// In either case, we can consider this a failure, and recycle the memory associated with this object.
		
		// Update state
		state = STATE_FAILURE;
		
		[logger setFailureReason:@"Timed out"];
		[self fail];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Finish and Cleanup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)succeedWithSocket:(AsyncUdpSocket *)sock host:(NSString *)host port:(UInt16)port
{
	DDLogInfo(@"STUNSocket: SUCCESS");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// Record finish time
	finishTime = [[NSDate alloc] init];
	
	// Update state
	state = STATE_DONE;
	
	// Connect the socket to it's remote host:port
	NSError *err = nil;
	if(![sock connectToHost:host onPort:port error:&err])
	{
		DDLogWarn(@"STUNSocket: Unable to connect socket to %@:%hu due to error: %@", host, port, err);
	}
	
	if([delegate respondsToSelector:@selector(stunSocket:didSucceed:)])
	{
		[delegate stunSocket:self didSucceed:sock];
	}
	
	[logger setRouterMapping:[[self class] routerTypeToMappingString:local_routerType]];
	[logger setRouterFiltering:[[self class] routerTypeToFilteringString:local_routerType]];
	[logger setSuccess:YES];
	[logger setSuccessCycle:attemptCount];
	[logger setReadValidation:readValidationComplete];
	[logger setWriteValidation:writeValidationComplete];
	[logger setDuration:[finishTime timeIntervalSinceDate:startTime]];
	[STUNUtilities sendStunFeedback:logger];
	
	[self cleanup];
}

- (void)fail
{
	DDLogInfo(@"STUNSocket: FAILURE");
	
	[logger addTraceMethod:NSStringFromSelector(_cmd)];
	[logger addTraceMessage:StringFromState(state)];
	
	// Record finish time
	finishTime = [[NSDate alloc] init];
	
	// Update state
	state = STATE_FAILURE;
	
	if([delegate respondsToSelector:@selector(stunSocketDidFail:)])
	{
		[delegate stunSocketDidFail:self];
	}
	
	[logger setRouterMapping:[[self class] routerTypeToMappingString:local_routerType]];
	[logger setRouterFiltering:[[self class] routerTypeToFilteringString:local_routerType]];
	[logger setSuccess:NO];
	[logger setSuccessCycle:attemptCount];
	
	if(readValidationComplete) {
		[logger setReadValidation:YES];
	}
	else if(readValidationFailed) {
		[logger setReadValidation:NO];
	}
	
	if(writeValidationComplete) {
		[logger setWriteValidation:YES];
	}
	
	[logger setDuration:[finishTime timeIntervalSinceDate:startTime]];
	[STUNUtilities sendStunFeedback:logger];
	
	[self cleanup];
}

- (void)cleanup
{
	DDLogVerbose(@"STUNSocket: cleanup");
	
	// Remove self as xmpp delegate
	[[MojoXMPPClient sharedInstance] removeDelegate:self];
	
	// Remove self from existingStuntSockets dictionary so we can be deallocated
	[existingStunSockets removeObjectForKey:uuid];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNXMPPMessage

+ (BOOL)isStunInviteMessage:(XMPPMessage *)message
{
	// Get x level information
	NSXMLElement *x = [message elementForName:@"x" xmlns:@"deusty:x:stun"];
	
	if(x)
	{
		NSString *type = [[x attributeForName:@"type"] stringValue];
		
		return [type isEqualToString:@"invite"];
	}
	
	return NO;
}

+ (STUNXMPPMessage *)messageFromMessage:(XMPPMessage *)message
{
	return [[[STUNXMPPMessage alloc] initFromMessage:message] autorelease];
}

+ (STUNXMPPMessage *)messageWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid
{
	return [[[STUNXMPPMessage alloc] initWithType:type to:to uuid:uuid] autorelease];
}

- (id)initFromMessage:(XMPPMessage *)message
{
	if((self = [super init]))
	{
		// Initialize any variables that need initialization
		port = 0;
		routerType = ROUTER_TYPE_UNKNOWN;
		
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
			routerType = [STUNSocket routerTypeFromString:[[x elementForName:@"router"] stringValue]];
			
			ip = [[[x elementForName:@"ip"] stringValue] copy];
			
			port = [[[x elementForName:@"port"] stringValue] intValue];
			
			portRange = NSRangeFromString([[x elementForName:@"portRange"] stringValue]);
		}
		else if([type isEqualToString:@"callback"])
		{
			port = [[[x elementForName:@"port"] stringValue] intValue];
			
			portRange = NSRangeFromString([[x elementForName:@"portRange"] stringValue]);
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
		
		version = STUN_VERSION;
		
		// Initialize any variables that need initialization
		port = 0;
		portRange = NSMakeRange(0, 0);
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
	
	[ip release];
	
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

- (RouterType)routerType {
	return routerType;
}
- (void)setRouterType:(RouterType)newRouterType {
	routerType = newRouterType;
}

- (NSString *)ip {
	return ip;
}
- (void)setIP:(NSString *)newIP
{
	if(![ip isEqualToString:newIP])
	{
		[ip release];
		ip = [newIP copy];
	}
}

- (UInt16)port {
	return port;
}
- (void)setPort:(UInt16)newPort {
	port = newPort;
}

- (NSRange)portRange {
	return portRange;
}
- (void)setPortRange:(NSRange)newPortRange {
	portRange = newPortRange;
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
	NSXMLElement *x = [NSXMLElement elementWithName:@"x" xmlns:@"deusty:x:stun"];
	[x addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:type]];
	[x addAttribute:[NSXMLNode attributeWithName:@"version" stringValue:version]];
	
	if([type isEqualToString:@"invite"] || [type isEqualToString:@"accept"])
	{
		if(routerType != ROUTER_TYPE_UNKNOWN)
		{
			NSString *routerTypeStr = [STUNSocket stringFromRouterType:routerType];
			[x addChild:[NSXMLNode elementWithName:@"router" stringValue:routerTypeStr]];
		}
		if(ip)
		{
			[x addChild:[NSXMLNode elementWithName:@"ip" stringValue:ip]];
		}
		if(port > 0)
		{
			NSString *portStr = [NSString stringWithFormat:@"%i", port];
			[x addChild:[NSXMLNode elementWithName:@"port" stringValue:portStr]];
		}
		if(portRange.location != 0)
		{
			NSString *portRangeStr = NSStringFromRange(portRange);
			[x addChild:[NSXMLNode elementWithName:@"portRange" stringValue:portRangeStr]];
		}
	}
	else if([type isEqualToString:@"callback"])
	{
		if(port > 0)
		{
			NSString *portStr = [NSString stringWithFormat:@"%i", port];
			[x addChild:[NSXMLNode elementWithName:@"port" stringValue:portStr]];
		}
		if(portRange.location != 0)
		{
			NSString *portRangeStr = NSStringFromRange(portRange);
			[x addChild:[NSXMLNode elementWithName:@"portRange" stringValue:portRangeStr]];
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

