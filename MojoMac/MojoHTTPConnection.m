#import "MojoHTTPConnection.h"
#import "MojoHTTPServer.h"
#import "HTTPResponse.h"
#import "HTTPAsyncFileResponse.h"
#import "MojoDefinitions.h"
#import "ITunesLocalSharedData.h"
#import "RHData.h"
#import "RHKeychain.h"
#import "STUNTSocket.h"
#import "SearchResponse.h"

@implementation MojoHTTPConnection

- (id)initWithAsyncSocket:(AsyncSocket *)newSocket forServer:(HTTPServer *)myServer
{
	if((self = [super initWithAsyncSocket:newSocket forServer:myServer]))
	{
		isMojoConnection = NO;
	}
	return self;
}

- (BOOL)isMojoConnection
{
	return isMojoConnection;
}

/**
 * Overrides HTTPConnection's method to secure connections to the server if needed.
**/
- (BOOL)isSecureServer
{
	// Todo: Implement support for TLS
//	return [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_TLS];
	
	return NO;
}

/**
 * Overrides HTTPConnection's method to provide the proper SSL Identity
**/
- (NSArray *)sslIdentityAndCertificates
{
	NSArray *result = [RHKeychain SSLIdentityAndCertificates];
	if([result count] == 0)
	{
		[RHKeychain createNewIdentity];
		return [RHKeychain SSLIdentityAndCertificates];
	}
	return result;
}

/**
 * Overrides HTTPConnection's method to determine password protection based on the user defaults
**/
- (BOOL)isPasswordProtected:(NSString *)path
{
	// We don't password protect the txt record data
	if(![path isEqualToString:@"/"])
	{
		if([[NSUserDefaults standardUserDefaults] boolForKey:PREFS_REQUIRE_PASSWORD])
		{
			NSString *password = [RHKeychain passwordForHTTPServer];
			return ((password != nil) && ([password length] > 0));
		}
	}
	return NO;
}

/**
 * Overrides HTTPConnection's method to provide a realm based on the iTunes library persistent ID
**/
- (NSString *)realm
{
	NSString *libID = [[ITunesLocalSharedData sharedLocalITunesData] libraryPersistentID];
	
	return [NSString stringWithFormat:@"%@@mojo.deusty.com", libID];
}

/**
 * Overrides HTTPConnection's method to provide the proper password set by the user.
**/
- (NSString *)passwordForUser:(NSString *)username
{
	// Ignore the username
	// We're using simple password protection
	return [RHKeychain passwordForHTTPServer];
}

- (NSString *)filePathForURI:(NSString *)path
{
	// The user is not requesting the XML file, so they must be requesting a song
	NSArray *components = [path pathComponents];
	
	if([components count] < 3)
	{
		// There must be at least 3 path components
		// The first component is just the leading '/' and is ignored
		// The second component is the track ID
		// The third component is the persistent track ID
		return nil;
	}
	
	int trackID = [[components objectAtIndex:1] intValue];
	NSString *persistentTrackID = [components objectAtIndex:2];
	
	// Get the local iTunesData
	ITunesLocalSharedData *data = [ITunesLocalSharedData sharedLocalITunesData];
	
	int validatedTrackID = [data validateTrackID:trackID withPersistentTrackID:persistentTrackID];
	
	NSDictionary *track = [data trackForID:validatedTrackID];
	
	// A request for anything but a file should be ignored
	if(![[track objectForKey:TRACK_TYPE] isEqualToString:@"File"])
	{
		return nil;
	}
	
	NSURL *songURL = [NSURL URLWithString:[track objectForKey:TRACK_LOCATION]];
	
	return [[songURL path] stringByStandardizingPath];
}

/**
 * Parses the query variables in the request URI.
 * 
 * For example, if the request URI was "search?q=John%20Mayer%20Trio&num=50"
 * then this method would return the following dictionary:
 * {
 *   q = "John Mayer Trio"
 *   num = "50"
 * }
**/
- (NSDictionary *)parseRequestQuery
{
	if(request == NULL) return nil;
	if(!CFHTTPMessageIsHeaderComplete(request)) return nil;
	
	CFURLRef url = CFHTTPMessageCopyRequestURL(request);
	
	if(url == NULL) return nil;
	
	NSString *query = [NSMakeCollectable(CFURLCopyQueryString(url, NULL)) autorelease];
	NSArray *components = [query componentsSeparatedByString:@"&"];
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[components count]];
	
	NSUInteger i;
	for(i = 0; i < [components count]; i++)
	{
		NSString *component = [components objectAtIndex:i];
		if([component length] > 0)
		{
			NSRange range = [component rangeOfString:@"="];
			if(range.location != NSNotFound)
			{
				NSString *escapedKey = [component substringToIndex:(range.location + 0)];
				NSString *escapedValue = [component substringFromIndex:(range.location + 1)];
				
				if([escapedKey length] > 0)
				{
					NSString *key, *value;
					
					key = [NSMakeCollectable(CFURLCreateStringByReplacingPercentEscapes(NULL,
																						(CFStringRef)escapedKey,
																						CFSTR(""))) autorelease];
					
					value = [NSMakeCollectable(CFURLCreateStringByReplacingPercentEscapes(NULL,
																						  (CFStringRef)escapedValue,
																						  CFSTR(""))) autorelease];
					
					if(key && value)
					{
						[result setObject:value forKey:key];
					}
				}
			}
		}
	}
	
	CFRelease(url);
	
	return result;
}

/**
 * Overrides HTTPConnection's method to handle custom non-file responses.
**/
- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path
{
	// First take care of the special (and common) cases of users requesting "/", "/xml", or "xml.zlib"
	if([path isEqualToString:@"/"])
	{
		// Requesting general information about our library (remote computers can't see our bonjour service)
		
		NSDictionary *info = [[MojoHTTPServer sharedInstance] TXTRecordDictionary];
		NSData *data = [NSNetService dataFromTXTRecordDictionary:info];
		
		return [[[HTTPDataResponse alloc] initWithData:data] autorelease];
	}
	else if([path isEqualToString:@"/xml"])
	{
		// Since the user is requesting the XML file, we know they're a MojoClient
		isMojoConnection = YES;
		
		ITunesLocalSharedData *iTunesData = [ITunesLocalSharedData sharedLocalITunesData];
		NSData *xmlData = [iTunesData serializedData];
				
		return [[[HTTPDataResponse alloc] initWithData:xmlData] autorelease];
	}
	else if([path isEqualToString:@"/xml.zlib"])
	{
		// Since the user is requesting the XML file, we know they're a MojoClient
		isMojoConnection = YES;
		
		ITunesLocalSharedData *iTunesData = [ITunesLocalSharedData sharedLocalITunesData];
		NSData *xmlData = [iTunesData serializedData];
		NSData *zlibData = [xmlData zlibDeflateWithCompressionLevel:9];
				
		return [[[HTTPDataResponse alloc] initWithData:zlibData] autorelease];
	}
	else if([path isEqualToString:@"/xml.gzip"])
	{
		// Since the user is requesting the XML file, we know they're a MojoClient
		isMojoConnection = YES;
		
		ITunesLocalSharedData *iTunesData = [ITunesLocalSharedData sharedLocalITunesData];
		NSData *xmlData = [iTunesData serializedData];
		NSData *gzipData = [xmlData gzipDeflateWithCompressionLevel:9];
		
		return [[[HTTPDataResponse alloc] initWithData:gzipData] autorelease];
	}
	else if([path hasPrefix:@"/search?"])
	{
		return [[[SearchResponse alloc] initWithQuery:[self parseRequestQuery]
										forConnection:self
										 runLoopModes:[asyncSocket runLoopModes]] autorelease];
	}
	
	// Handle regular file requests as usual
	return [super httpResponseForMethod:method URI:path];
}

- (void)handleUnknownMethod:(NSString *)method
{
	if([method isEqualToString:@"STUNT"])
	{
		BOOL result = [STUNTSocket handleSTUNTRequest:request fromSocket:asyncSocket];
		
		if(result)
		{
			[self abandonSocketAndDie];
		}
		else
		{
			[super handleUnknownMethod:method];
		}
	}
	else
	{
		[super handleUnknownMethod:method];
	}
}

- (NSData *)preprocessResponse:(CFHTTPMessageRef)response
{
	NSString *filePath = nil;
	
	if([httpResponse isKindOfClass:[HTTPFileResponse class]])
	{
		filePath = [(HTTPFileResponse *)httpResponse filePath];
	}
	else if([httpResponse isKindOfClass:[HTTPAsyncFileResponse class]])
	{
		filePath = [(HTTPAsyncFileResponse *)httpResponse filePath];
	}
	
	if(filePath)
	{
		// Add proper content type headers to support the iPhone
		
		NSString *fileExtension = [filePath pathExtension];
		
		if([fileExtension isEqualToString:@"mp3"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("audio/mpeg"));
		}
		else if([fileExtension isEqualToString:@"aac"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("audio/aac"));
		}
		else if([fileExtension isEqualToString:@"m4a"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("audio/aac"));
		}
		else if([fileExtension isEqualToString:@"m4p"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("audio/aac"));
		}
		else if([fileExtension isEqualToString:@"mov"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("video/quicktime"));
		}
		else if([fileExtension isEqualToString:@"mp4"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("video/mp4"));
		}
		else if([fileExtension isEqualToString:@"m4v"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("video/x-m4v"));
		}
		else if([fileExtension isEqualToString:@"3gp"])
		{
			CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), CFSTR("video/3gpp"));
		}
	}
	
	return [super preprocessResponse:response];
}

- (void)abandonSocketAndDie
{
	if([asyncSocket delegate] == self)
	{
		[asyncSocket setDelegate:nil];
	}
	[asyncSocket release];
	asyncSocket = nil;
	
	[self die];
}

@end
