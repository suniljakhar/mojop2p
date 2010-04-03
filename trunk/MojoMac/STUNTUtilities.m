/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "STUNTUtilities.h"
#import "RHURL.h"
#import "MojoDefinitions.h"

#import <sys/types.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <stdlib.h>

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 3
#else
  #define DEBUG_LEVEL 3
#endif
#include "DDLog.h"


@implementation STUNTUtilities

/**
 * Returns a random port number is the range (8001 - 63024) inclusive.
**/
+ (int)randomPortNumber
{
	return 8001 + (arc4random() % (63025 - 8001));
}

/**
 * Returns the global IPv6 address if one is available, nil otherwise.
**/
+ (NSString *)globaIPv6Address
{
	struct ifaddrs *ifap, *ifp;
	
	if(getifaddrs(&ifap) < 0)
	{
		return nil;
	}
	
	NSData *sockaddr_data = nil;
	
	for(ifp = ifap; ifp && !sockaddr_data; ifp = ifp->ifa_next) 
	{
		// Ignore everything but IPv6
		if(ifp->ifa_addr->sa_family != AF_INET6) continue;
		
		struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifp->ifa_addr;
		
		// Ignore link-local IPv6 addresses
		if(sin6->sin6_scope_id == 0)
		{
			NSString *ifname = [NSString stringWithFormat:@"%s", ifp->ifa_name];
			
			// Ignore loopback addresses
			if(![ifname hasPrefix:@"lo"])
			{
				sockaddr_data = [NSData dataWithBytes:sin6 length:sin6->sin6_len];
			}
		}
	}
	
	freeifaddrs(ifap);
	
	if(sockaddr_data)
	{
		struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)[sockaddr_data bytes];
		
		char addr[INET6_ADDRSTRLEN];
		if(inet_ntop(AF_INET6, &sin6->sin6_addr, addr, sizeof(addr)))
		{
			return [NSString stringWithFormat:@"%s", addr];
		}
		else
		{
			return nil;
		}
	}
	else
	{
		return nil;
	}
}

/**
 * This method synchronously downloads the given URL.
 * Before connecting to the remote host, it first binds to the given local port number.
 * The timeout is the max amount of time to wait for the connection to the host to succeed.
**/
+ (NSData *)downloadURL:(NSURL *)url onLocalPort:(int)localPortNumber timeout:(NSTimeInterval)connectTimeout
{
	int result;
	
	DDLogVerbose(@"STUNTUtilities: Looking up IP address...");
	
	struct hostent *hostInfo = gethostbyname2([[url host] UTF8String], AF_INET);
	
	if(hostInfo == NULL)
	{
		DDLogError(@"STUNTUtilities: Error - Could not get IP address for '%@'", [url host]);
		return nil;
	}
	
	DDLogVerbose(@"STUNTUtilities: Creating socket...");
	
	int nativeSocket = socket(AF_INET, SOCK_STREAM, 0);
	
	if(nativeSocket == -1)
	{
		DDLogError(@"STUNTUtilities: Error - Could not make a socket: %d: %s", errno, strerror(errno));
		return nil;
	}
	
	DDLogVerbose(@"STUNTUtilities: Setting socket options...");
	
	// Reuse the address so we can use the same port several times in a row
	int yes = 1;
	result = setsockopt(nativeSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int));
	
	if(result == -1)
	{
		DDLogError(@"STUNTUtilities: Error - Couldn't setsockopt to reuseaddr: %d: %s", errno, strerror(errno));
		close(nativeSocket);
		return nil;
	}
	
	if(localPortNumber > 0)
	{
		DDLogVerbose(@"STUNTUtilities: Binding socket to local port...");
		
		struct sockaddr_in localAddress;
		localAddress.sin_len = sizeof(struct sockaddr_in);
		localAddress.sin_family = AF_INET;
		localAddress.sin_port = htons(localPortNumber);
		localAddress.sin_addr.s_addr = htonl(INADDR_ANY);
		memset(localAddress.sin_zero, 0, sizeof(localAddress.sin_zero));
		
		result = bind(nativeSocket, (struct sockaddr *)&localAddress, sizeof(localAddress));
		
		if(result == -1)
		{
			DDLogError(@"STUNTUtilities: Error - Could not bind socket: %d: %s", errno, strerror(errno));
			close(nativeSocket);
			return nil;
		}
	}
	
	DDLogVerbose(@"STUNTUtilities: Creating remoteAddress...");
	
	int remotePortNumber = [[url port] intValue];
	if(remotePortNumber == 0)
	{
		remotePortNumber = 80;
	}
	
	struct sockaddr_in remoteAddress;
	remoteAddress.sin_len = sizeof(struct sockaddr_in);
	remoteAddress.sin_family = AF_INET;
	remoteAddress.sin_port = htons(remotePortNumber);
	remoteAddress.sin_addr = *((struct in_addr *)(hostInfo->h_addr));
	memset(&(remoteAddress.sin_zero), 0, sizeof(remoteAddress.sin_zero));
	
	DDLogVerbose(@"STUNTUtilities: Creating CFSocket from native socket...");
	
	CFSocketRef socket = CFSocketCreateWithNative(NULL, nativeSocket, kCFSocketNoCallBack, NULL, NULL);
	if(socket == NULL)
	{
		DDLogError(@"STUNTUtilities: Error - Could not create CFSocket from native socket");
		close(nativeSocket);
		return NO;
	}
	
	DDLogVerbose(@"STUNTUtilities: Connecting to host...");
	
	CFDataRef remoteAddrData;
	remoteAddrData = CFDataCreateWithBytesNoCopy(NULL,
												 (UInt8 *)(&remoteAddress),
												 sizeof(struct sockaddr_in),
												 kCFAllocatorNull);
	
	if(remoteAddrData == NULL)
	{
		DDLogError(@"STUNTUtilities: Error - Could not create CFDataRef from struct sockaddr_in");
		CFSocketInvalidate(socket);
		CFRelease(socket);
		return nil;
	}
	
	CFSocketError err = CFSocketConnectToAddress(socket, remoteAddrData, connectTimeout);
	
	CFRelease(remoteAddrData);
	
	if(err != kCFSocketSuccess)
	{
		if(DEBUG_ERROR)
		{
			if(err == kCFSocketTimeout)
			{
				DDLogError(@"STUNTUtilities: Timeout connecting to host: %@", [url host]);
			}
			else
			{
				DDLogError(@"STUNTUtilities: Error connecting to host: %@", [url host]);
			}
		}
		
		CFSocketInvalidate(socket);
		CFRelease(socket);
		return nil;
	}
	
	DDLogVerbose(@"STUNTUtilities: Writing data...");
	
	CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), (CFURLRef)url, kCFHTTPVersion1_1);
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Host"), (CFStringRef)[url host]);
	CFDataRef outData = CFHTTPMessageCopySerializedMessage(request);
	
	int outBufferLength = CFDataGetLength(outData);
	UInt8 outBuffer[outBufferLength];
	CFDataGetBytes(outData, CFRangeMake(0, outBufferLength), outBuffer);
	
	CFRelease(outData);
	CFRelease(request);
	
	result = write(nativeSocket, outBuffer, outBufferLength);
	
	if(result == -1)
	{
		DDLogError(@"STUNTUtilities: Error - Error writing: %d: %s", errno, strerror(errno));
		CFSocketInvalidate(socket);
		CFRelease(socket);
		return nil;
	}
	
	DDLogVerbose(@"STUNTUtilities: Reading data...");
	
	// Start reading in the response
	// We're going to add all the response data to a CFHTTPMessageRef
	CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
	
	do
	{
		UInt8 inBuffer[128];
		result = read(nativeSocket, inBuffer, 128);
		
		if(result == -1)
		{
			DDLogError(@"STUNTUtilities: Error - Error reading: %d: %s", errno, strerror(errno));
			
			CFSocketInvalidate(socket);
			CFRelease(socket);
			
			CFRelease(response);
			
			return nil;
		}
		else
		{
			CFHTTPMessageAppendBytes(response, inBuffer, result);
		}
		
	} while(result == 128);
	
	// Figure out if chunked transfer encoding was used
	NSString *transferEncoding = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Transfer-Encoding"));
	[transferEncoding autorelease];
	
	if(![transferEncoding isEqualToString:@"chunked"])
	{
		// Chunked transfer encoding wasn't used, so we're done!
		NSData *result = (NSData *)CFHTTPMessageCopyBody(response);
		
		CFSocketInvalidate(socket);
		CFRelease(socket);
		
		CFRelease(response);
		
		return [result autorelease];
	}
	
	DDLogVerbose(@"Extracting data...");
	
	// Now we have to get rid of any chunked transfer encoding crap in the body
	NSData *inData = [(NSData *)CFHTTPMessageCopyBody(response) autorelease];
	NSMutableString *body = [[[NSMutableString alloc] initWithData:inData encoding:NSUTF8StringEncoding] autorelease];
	
	NSMutableString *strippedBody = [NSMutableString stringWithCapacity:[body length]];
	
	NSRange crlf;
	BOOL isJunk = YES;
	
	do
	{
		// Search for CRLF (Carriage return, New line) sequences
		crlf = [body rangeOfString:@"\r\n"];
		
		if(crlf.location != NSNotFound)
		{
			if(!isJunk)
			{
				[strippedBody appendString:[body substringWithRange:NSMakeRange(0, crlf.location)]];
			}
			isJunk = !isJunk;
			[body deleteCharactersInRange:NSMakeRange(0, crlf.location + crlf.length)];
		}
		
	} while(crlf.location != NSNotFound);
	
	CFSocketInvalidate(socket);
	CFRelease(socket);
	
	CFRelease(response);
	
	return [strippedBody dataUsingEncoding:NSUTF8StringEncoding];
}

+ (void)sendStuntFeedback:(STUNTLogger *)logger
{
	if(![[NSUserDefaults standardUserDefaults] boolForKey:PREFS_STUNT_FEEDBACK]) return;
	
	NSData *postData = [logger postData];
	NSString *lengthStr = [NSString stringWithFormat:@"%qu", (UInt16)[postData length]];
	
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:@"http://www.deusty.com/stunt/feedback.php"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:lengthStr forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPBody:postData];
	
	NSURLDownload *urlDownload;
	urlDownload = [[NSURLDownload alloc] initWithRequest:request delegate:self];
	
	// We release urlDownload within the delegate methods
}

+ (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	[download autorelease];
	DDLogError(@"STUNTUtilities: Failed sending anonymous STUNT protocol statistics.");
}

+ (void)downloadDidFinish:(NSURLDownload *)download
{
	[download autorelease];
	DDLogInfo(@"STUNTUtilities: Finished sending anonymous STUNT protocol statistics.");
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNTPortPredictionLogger

- (id)initWithLocalPort:(UInt16)port
{
	if((self = [super init]))
	{
		localPort = port;
		reportedPort1 = 0;
		reportedPort2 = 0;
		predictedPort1 = 0;
		predictedPort2 = 0;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (UInt16)localPort
{
	return localPort;
}

- (UInt16)reportedPort1
{
	return reportedPort1;
}
- (void)setReportedPort1:(UInt16)port
{
	reportedPort1 = port;
}

- (UInt16)reportedPort2
{
	return reportedPort2;
}
- (void)setReportedPort2:(UInt16)port
{
	reportedPort2 = port;
}

- (UInt16)predictedPort1
{
	return predictedPort1;
}
- (void)setPredictedPort1:(UInt16)port
{
	predictedPort1 = port;
}

- (UInt16)predictedPort2
{
	return predictedPort2;
}
- (void)setPredictedPort2:(UInt16)port
{
	predictedPort2 = port;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNTLogger

static NSString *systemVersion;

+ (NSString *)machineUUID
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:STUNT_UUID];
}

+ (NSString *)systemVersion
{
	if(!systemVersion)
	{
		NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
		
		systemVersion = [[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"];
		[systemVersion retain];
	}
	return systemVersion;
}

- (id)initWithSTUNTUUID:(NSString *)uuid version:(NSString *)version
{
	if((self = [super init]))
	{
		stuntUUID = [uuid copy];
		stuntVersion = [version copy];
		
		portPredictions = [[NSMutableArray alloc] initWithCapacity:4];
		
		portMappingAvailable = NO;
		connectionViaServer = NO;
		
		duration = 0;
		
		success = NO;
		cycle = 0;
		state = 0;
		
		validation = STUNT_VALIDATION_NONE;
		
		trace = [[NSMutableString alloc] initWithCapacity:150];
	}
	return self;
}

- (void)dealloc
{
	[stuntUUID release];
	[stuntVersion release];
	[routerManufacturer release];
	[portPredictions release];
	[portMappingProtocol release];
	[failureReason release];
	[trace release];
	[super dealloc];
}

- (void)setRouterManufacturer:(NSString *)manufacturer
{
	if(routerManufacturer != manufacturer)
	{
		[routerManufacturer release];
		routerManufacturer = [manufacturer copy];
	}
}

- (void)addPortPredictionLogger:(STUNTPortPredictionLogger *)ppLogger
{
	[portPredictions addObject:ppLogger];
}

- (void)setPortMappingAvailable:(BOOL)flag
{
	portMappingAvailable = flag;
}

- (void)setPortMappingProtocol:(NSString *)protocol
{
	if(portMappingProtocol != protocol)
	{
		[portMappingProtocol release];
		portMappingProtocol = [protocol copy];
	}
}

- (void)setConnectionViaServer:(BOOL)flag
{
	connectionViaServer = flag;
}

- (void)setDuration:(NSTimeInterval)total
{
	duration = total;
}

- (void)setSuccess:(BOOL)flag
{
	success = flag;
}
- (void)setSuccessCycle:(int)successCycle
{
	cycle = successCycle;
}
- (void)setSuccessState:(int)successState
{
	state = successState;
}

- (void)setValidation:(int)validationConstant
{
	validation = validationConstant;
}

- (void)setFailureReason:(NSString *)reason
{
	if(failureReason != reason)
	{
		[failureReason release];
		failureReason = [reason copy];
	}
}

- (void)addTraceMethod:(NSString *)method
{
	[trace appendFormat:@"[%@]", method];
}

- (void)addTraceMessage:(NSString *)message, ...
{
	va_list arguments;
	va_start(arguments, message);
	
	NSString *msg = [[NSString alloc] initWithFormat:message arguments:arguments];
	
	[trace appendFormat:@"(%@)", msg];
	[msg release];
}

- (NSData *)postData
{
	NSMutableString *post = [NSMutableString stringWithCapacity:250];
	
	NSString *machineUUID = [[self class] machineUUID];
	
	NSString *osVersion = [[self class] systemVersion];
	
	NSString *versionNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *buildNumber   = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	
	NSString *mojoVersion = [NSString stringWithFormat:@"%@ (%@)", versionNumber, buildNumber];
	
	[post appendFormat:@"computerUUID=%@&", [NSURL urlEncodeValue:machineUUID]];
	[post appendFormat:@"mojoVersion=%@&", [NSURL urlEncodeValue:mojoVersion]];
	[post appendFormat:@"stuntUUID=%@&", [NSURL urlEncodeValue:stuntUUID]];
	[post appendFormat:@"stuntVersion=%@&", [NSURL urlEncodeValue:stuntVersion]];
	[post appendFormat:@"osVersion=%@&", [NSURL urlEncodeValue:osVersion]];
	
	if(routerManufacturer)
	{
		[post appendFormat:@"routerManufacturer=%@&", [NSURL urlEncodeValue:routerManufacturer]];
	}
	
	[post appendFormat:@"portMappingAvailable=%d&", portMappingAvailable];
	
	if(portMappingProtocol)
	{
		[post appendFormat:@"portMappingProtocol=%@&", [NSURL urlEncodeValue:portMappingProtocol]];
	}
	
	[post appendFormat:@"connectionViaServer=%d&", connectionViaServer];
	
	[post appendFormat:@"duration=%f&", duration];
	
	[post appendFormat:@"success=%d&", success];
	[post appendFormat:@"successCycle=%i&", cycle];
	[post appendFormat:@"successState=%i&", state];
	
	[post appendFormat:@"validation=%i&", validation];
	
	if(failureReason)
	{
		[post appendFormat:@"failureReason=%@&", [NSURL urlEncodeValue:failureReason]];
	}
	
	if([trace length] > 0)
	{
		[post appendFormat:@"trace=%@&", [NSURL urlEncodeValue:trace]];
	}
	
	uint i;
	for(i = 0; i < [portPredictions count]; i++)
	{
		STUNTPortPredictionLogger *ppLogger = [portPredictions objectAtIndex:i];
		
		[post appendFormat:@"pp%i_localPort=%hu&",      i, [ppLogger localPort]];
		[post appendFormat:@"pp%i_reportedPort1=%hu&",  i, [ppLogger reportedPort1]];
		[post appendFormat:@"pp%i_reportedPort2=%hu&",  i, [ppLogger reportedPort2]];
		[post appendFormat:@"pp%i_predictedPort1=%hu&", i, [ppLogger predictedPort1]];
		[post appendFormat:@"pp%i_predictedPort2=%hu&", i, [ppLogger predictedPort2]];
	}
	
	return [post dataUsingEncoding:NSUTF8StringEncoding];
}

@end

