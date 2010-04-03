#import "MojoHTTPServer.h"
#import "MojoHTTPConnection.h"
#import "MojoDefinitions.h"
#import "RHKeychain.h"
#import "AsyncSocket.h"
#import "TigerSupport.h"


@implementation MojoHTTPServer

// CLASS VARIABLES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static MojoHTTPServer *sharedInstance;

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
		sharedInstance = [[MojoHTTPServer alloc] init];
	}
}

/**
 * Returns the shared instance that all objects in this application can use.
**/
+ (MojoHTTPServer *)sharedInstance
{
	return sharedInstance;
}

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard Constructor.
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
		// Configure server to run on common run loop modes.
		// This allows the server to remain responsive even when the menu is in use.
		[asyncSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
		
		// Configure HTTP server as a Mojo server
		int serverPort = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_SERVER_PORT_NUMBER];
		
		if((serverPort != 0) && (serverPort < 1024 && serverPort > 65535))
		{
			// Invalid port number - reset the port to zero
			serverPort = 0;
		}
		
		[self setPort:serverPort];
		[self setType:MOJO_SERVICE_TYPE];
		[self setConnectionClass:[MojoHTTPConnection class]];
	}
	return self;
}

/**
 * Standard Destructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
	[super dealloc];
}

/**
 * Configures the txtRecordData for the bonjour service.
 * The parameters are the needed information to complete the txtRecord dictionary.
**/
- (void)setITunesLibraryID:(NSString *)libID numberOfSongs:(int)numSongs
{
	if([self TXTRecordDictionary] == nil)
	{
		// Configure TXT record for the first time
		
		NSMutableDictionary *txtRecordDict = [NSMutableDictionary dictionaryWithCapacity:5];
		
		NSString *reqPasswd = @"0";
		if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD])
		{
			NSString *password = [RHKeychain passwordForHTTPServer];
			if((password != nil) && ([password length] > 0))
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
		if(shareName == nil)
		{
			shareName = @"";
		}
		
		NSString *numSongsStr = [NSString stringWithFormat:@"%i", numSongs];
		
		[txtRecordDict setObject:@"2"        forKey:TXTRCD_VERSION];
		[txtRecordDict setObject:@"1"        forKey:TXTRCD_ZLIB_SUPPORT];
		[txtRecordDict setObject:@"1"        forKey:TXTRCD_GZIP_SUPPORT];
		[txtRecordDict setObject:@"1.1"      forKey:TXTRCD_STUNT_VERSION];
		[txtRecordDict setObject:@"1.0"      forKey:TXTRCD_STUN_VERSION];
		[txtRecordDict setObject:@"1.0"      forKey:TXTRCD_SEARCH_VERSION];
		[txtRecordDict setObject:reqPasswd   forKey:TXTRCD_REQUIRES_PASSWORD];
		[txtRecordDict setObject:libID       forKey:TXTRCD2_LIBRARY_ID];
		[txtRecordDict setObject:shareName   forKey:TXTRCD2_SHARE_NAME];
		[txtRecordDict setObject:numSongsStr forKey:TXTRCD2_NUM_SONGS];
		
		[self setTXTRecordDictionary:txtRecordDict];
	}
	else
	{
		// Update existing TXT record
		
		NSMutableDictionary *txtRecordDict = [[[self TXTRecordDictionary] mutableCopy] autorelease];
		
		NSString *numSongsStr = [NSString stringWithFormat:@"%i", numSongs];
		
		[txtRecordDict setObject:libID       forKey:TXTRCD2_LIBRARY_ID];
		[txtRecordDict setObject:numSongsStr forKey:TXTRCD2_NUM_SONGS];
		
		[self setTXTRecordDictionary:txtRecordDict];
	}
}

/**
 * This method forces an update of the TXTRecordData for the published bonjour service.
 * This should be called to propogate a new share name.
**/
- (void)updateShareName
{
	NSMutableDictionary *txtRecordDict = [[[self TXTRecordDictionary] mutableCopy] autorelease];
	
	NSString *shareName = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_SHARE_NAME];
	
	// Theoretically the shareName should never be nil.
	// But if an unknown set of circumstances caused it to be nil at some point,
	// then attempting to insert nil into the dictionary below would cause a crash.
	if(shareName == nil)
	{
		shareName = @"";
	}
	
	[txtRecordDict setObject:shareName forKey:TXTRCD2_SHARE_NAME];
	
	[self setTXTRecordDictionary:txtRecordDict];
}

/**
 * This method forces an update of the TXTRecordData for the published bonjour service.
 * This should be called when the status of the password protection is changed.
**/
- (void)updateRequiresPassword
{
	NSMutableDictionary *txtRecordDict = [[[self TXTRecordDictionary] mutableCopy] autorelease];
	
	BOOL requiresPassword = NO;
	if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD])
	{
		NSString *password = [RHKeychain passwordForHTTPServer];
		requiresPassword = ((password != nil) && ([password length] > 0));
	}
	
	if(requiresPassword)
		[txtRecordDict setObject:@"1" forKey:TXTRCD_REQUIRES_PASSWORD];
	else
		[txtRecordDict setObject:@"0" forKey:TXTRCD_REQUIRES_PASSWORD];
	
	[self setTXTRecordDictionary:txtRecordDict];
}

/**
 * This method forces an update of the TXTRecordData for the published bonjour service.
 * This should be called when the status of the password protection is changed.
**/
- (void)updateRequiresTLS
{
//	NSMutableDictionary *txtRecordDict = [[[self TXTRecordDictionary] mutableCopy] autorelease];
//	
//	// Todo: Implement support for TLS
//	BOOL requiresTLS = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_TLS];
//	BOOL requiresTLS = NO;
//	
//	if(requiresTLS)
//		[txtRecordDict setObject:@"1" forKey:TXTRCD_REQUIRES_TLS];
//	else
//		[txtRecordDict setObject:@"0" forKey:TXTRCD_REQUIRES_TLS];
//	
//	[self setTXTRecordDictionary:txtRecordDict];
}

/**
 * Returns the number of Mojo Connections.
 * That is, the number of connections from a MojoClient.
**/
- (int)numberOfMojoConnections
{
	int total = 0;
	
	@synchronized(connections)
	{
		uint i;
		for(i = 0; i < [connections count]; i++)
		{
			if([[connections objectAtIndex:i] isMojoConnection])
			{
				total++;
			}
		}
	}
	
	return total;
}

- (void)addConnection:(id)newSocket
{
	id newConnection = [[connectionClass alloc] initWithAsyncSocket:(AsyncSocket *)newSocket forServer:self];
	
	@synchronized(connections)
	{
		[connections addObject:newConnection];
	}
	
	if([newSocket isKindOfClass:[AsyncSocket class]])
	{
		// Under normal circumstances the HTTPConnection will wait until the onSocket:didConnectToHost:port:
		// method is invoked to start reading the header.  But since we've already opened the socket, this
		// method will never get called. To get around this little problem, we manually invoke the method here.
		[newConnection onSocket:newSocket didConnectToHost:[newSocket connectedHost] port:[newSocket connectedPort]];
	}
	else
	{
		// The newSocket is a PseudoAsyncSocket instance.
		// It should properly call onSocket:didConnectToHost:port: after its completed the TCP handshake.
	}
	
	[newConnection release];
}

/**
 * Bonjour delegate method.
 * This method overrides the corresponding stub method in the HTTP Server.
**/
- (void)netServiceDidPublish:(NSNetService *)ns
{
	// Output log message
	NSLog(@"Bonjour Service Published: domain(%@) type(%@) name(%@)", [ns domain], [ns type], [ns name]);
	
	// Post notification of published service
	[[NSNotificationCenter defaultCenter] postNotificationName:DidPublishServiceNotification object:ns];
}

@end
