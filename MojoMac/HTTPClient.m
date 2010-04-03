#import "HTTPClient.h"
#import "AsyncSocket.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 3
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

// Define read chunksize
#if TARGET_OS_IPHONE
  #define READ_CHUNKSIZE  (1024 * 64)
#else
  #define READ_CHUNKSIZE  (1024 * 64)
#endif

// Define the various timeouts (in seconds) for retreiving various parts of the HTTP response
#define WRITE_TIMEOUT             30
#define READ_FIRST_HEADER_TIMEOUT 30
#define READ_HEADER_TIMEOUT       20
#define READ_FOOTER_TIMEOUT       20
#define READ_CHUNKSIZE_TIMEOUT    20
#define READ_BODY_TIMEOUT         -1

// Define the various tags we'll use to differentiate what it is we're currently downloading
#define HTTP_HEADERS              10015
#define HTTP_BODY                 10030
#define HTTP_BODY_IGNORE          10031
#define HTTP_BODY_CHUNKED         10040
#define HTTP_BODY_CHUNKED_IGNORE  10041

// Define the various stages of downloading a chunked resource
#define CHUNKED_STAGE_SIZE         1
#define CHUNKED_STAGE_DATA         2
#define CHUNKED_STAGE_FOOTER       3


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation HTTPClient

/**
 * Default Constructor.
**/
- (id)init
{
	if((self = [super init]))
	{
		asyncSocket = [[AsyncSocket alloc] initWithDelegate:self];
		
		isProcessingRequestOrResponse = NO;
		
		fileSizeInBytes = 0;
		totalBytesReceived = 0;
		progressOfCurrentRead = 0;
		
		haveUsedExistingCredentials = NO;
	}
	return self;
}

/**
 * Creates a new HTTPClient using the given already connected socket.
 * The HTTPClient will take over ownership of the socket, retaining it, and setting itself as the new socket delegate.
**/
- (id)initWithSocket:(AsyncSocket *)socket baseURL:(NSURL *)baseURL
{
	if((self = [super init]))
	{
		asyncSocket = [socket retain];
		[asyncSocket setDelegate:self];
		
		currentURL = [baseURL copy];
		
		isProcessingRequestOrResponse = NO;
		
		fileSizeInBytes = 0;
		totalBytesReceived = 0;
		progressOfCurrentRead = 0;
		
		haveUsedExistingCredentials = NO;
	}
	return self;
}

/**
 * Standard dealloc method
**/
- (void)dealloc
{
	[asyncSocket setDelegate:nil];
	[asyncSocket disconnect];
	[asyncSocket release];
	[currentURL release];
	
	[filePath release];
	[file closeFile];
	[file release];
	
	if(request)  CFRelease(request);
	if(response) CFRelease(response);
	if(auth)     CFRelease(auth);
	
	[username release];
	[password release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Helper Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Releases and clears all variables related to a single download.
 * It's a good idea to call this method before and after a download.
**/
- (void)cleanup
{
	// Do not alter the filePath or currentURL variables here.
	// These should remain until the user requests another download.
	
	[file closeFile];
	[file release];
	file = nil;
	
	if(request)
	{
		CFRelease(request);
		request = NULL;
	}
	
	if(response)
	{
		CFRelease(response);
		response = NULL;
	}
	
	isProcessingRequestOrResponse = NO;
	
	fileSizeInBytes = 0;
	totalBytesReceived = 0;
	progressOfCurrentRead = 0;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)delegate
{
	return delegate;
}

- (void)setDelegate:(id)newDelegate
{
	delegate = newDelegate;
}

- (void)setSocket:(AsyncSocket *)socket baseURL:(NSURL *)baseURL
{
	[asyncSocket setDelegate:nil];
	[asyncSocket disconnect];
	[asyncSocket release];
	
	asyncSocket = [socket retain];
	[asyncSocket setDelegate:self];
	
	[currentURL release];
	currentURL = [baseURL copy];
	
	[self cleanup];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Download Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Private method to handle adding authentication, preparing the empty response message, and sending the request.
**/
- (void)sendRequest
{
	// Do we have any authentication information we need to add to our request???
	if(auth && username && password)
	{
		CFHTTPMessageApplyCredentials(request, auth, (CFStringRef)username, (CFStringRef)password, NULL);
		haveUsedExistingCredentials = YES;
	}
	
	// Create empty HTTP Message response
	// The data we get from the web server will be stuffed in this message
	if(response) 
	{
		CFRelease(response);
		response = nil;
	}
	response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
	
	// Prepare the data to fire off over the connection
	NSData *data = [(NSData *)CFHTTPMessageCopySerializedMessage(request) autorelease];
	
	if(DEBUG_VERBOSE)
	{
		NSString *temp = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		DDLogVerbose(@"HTTPClient: Sending Request:\n%@", temp);
	}
	
	// Reset transmission variables
	isProcessingRequestOrResponse = YES;
	fileSizeInBytes = 0;
	totalBytesReceived = 0;
	progressOfCurrentRead = 0;
	
	// Send the request
	[asyncSocket writeData:data withTimeout:WRITE_TIMEOUT tag:HTTP_HEADERS];
}

/**
 * Public method to begin downloading a given URL.
 * If a download is already in progress, it is immediately cancelled without notification.
 * If the port is not specified in the URL, then the default HTTP ports are used. (80 for http, and 443 for https)
**/
- (void)downloadURL:(NSURL *)url toFile:(NSString *)aFilePath
{
	DDLogVerbose(@"HTTPClient: downloadURL:%@ toFile:%@", url, aFilePath);
	
	if(isProcessingRequestOrResponse)
	{
		DDLogWarn(@"HTTPClient: Ignoring download request - in the middle of a previous request");
		return;
	}
	
	[self cleanup];
	
	// Figure out the port to use for the new URL
	int newPort = [[url port] intValue];
	if(newPort == 0)
	{
		if([[url scheme] isEqualToString:@"https"])
			newPort = 443;
		else
			newPort = 80;
	}
	
	// Figure out the port we were using for our old URL
	int oldPort = [[currentURL port] intValue];
	if(oldPort == 0)
	{
		if([[currentURL scheme] isEqualToString:@"https"])
			oldPort = 443;
		else
			oldPort = 80;
	}
	
	if([[currentURL host] isEqualToString:@"localhost"])
	{
		// We've probably been disconnected, and AsyncSocket didn't tell us about it for some reason...
		[asyncSocket setDelegate:nil];
		[asyncSocket disconnect];
		[asyncSocket setDelegate:self];
	}
	
	// If we're not connected to anything
	// Or we're connected to a different host
	// Or we're connected to a different port
	// Then we need to connect to the new host/port in the given URL
	
	// Note that [asyncSocket connectedHost] returns an IP address,
	// while [url host] simply returns the host regardless of whether it's an IP address or URI name.
	if(![asyncSocket isConnected] || ![[currentURL host] isEqualToString:[url host]] || (oldPort != newPort))
	{
		DDLogInfo(@"HTTPClient: Creating new connection...");
		
		if([asyncSocket isConnected])
		{
			[asyncSocket setDelegate:nil];
			[asyncSocket disconnect];
			[asyncSocket setDelegate:self];
		}
		
		// Store reference to the currentURL we are using
		// We must store the new URL in the currentURL variable prior to calling connectToHost:onPort:error:
		// This is because onSocketWillConnect: will be immediately called, and it will need to know the currentURL
		// Because it must decide if a secure connection is needed
		[currentURL release];
		currentURL = [url copy];
		
		// We're ready to connect to the remote host
		[asyncSocket connectToHost:[url host] onPort:newPort error:nil];
	}
	else
	{
		DDLogInfo(@"HTTPClient: Recycling existing connection...");
		
		// The new URL resides on the same host (and port number) as the old URL
		// We should go ahead and update the currentURL variable anyways to be precise
		[currentURL release];
		currentURL = [url copy];
	}
	
	// Create HTTP Message request
	request = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("GET"), (CFURLRef)url, kCFHTTPVersion1_1);
	
	// Remember: The Host header field is required as of HTTP version 1.1
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Host"), (CFStringRef)[url host]);
	
	// Create the file (if needed) and open file handle for writing
	[filePath release];
	if(aFilePath)
	{
		filePath = [aFilePath copy];
	}
	else
	{
		NSString *template = @"tmp.XXXXXX";
		char *temp = mktemp((char *)[template UTF8String]);
		
		NSString *tempDir = NSTemporaryDirectory();
		NSString *tempFile = [NSString stringWithUTF8String:temp];
		
		filePath = [[tempDir stringByAppendingPathComponent:tempFile] copy];
	}
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
		DDLogVerbose(@"HTTPClient: Creating file: %@", filePath);
		
		if(![[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil])
		{
			DDLogError(@"HTTPClient: Unable to create file: %@", filePath);
		}
	}
	file = [[NSFileHandle fileHandleForWritingAtPath:filePath] retain];
	
	// Inovke private method to handle the common procedures for sending a request
	[self sendRequest];
}

/**
 * Immediately aborts the current download.
 * No delegate methods will be called.
**/
- (void)abort
{
	[asyncSocket setDelegate:nil];
	[asyncSocket disconnect];
	[asyncSocket release];
	asyncSocket = nil;
	
	[self cleanup];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Authentication
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the latest username set for use as authentication
**/
- (NSString *)username
{
	return username;
}

/**
 * Returns the latest password set for use as authentication
**/
- (NSString *)password
{
	return password;
}

/**
 * The method sets the username and password to be used for any authentication.
**/
- (void)setUsername:(NSString *)aUsername password:(NSString *)aPassword
{
	if(![username isEqualToString:aUsername])
	{
		[username release];
		username = [aUsername copy];
		haveUsedExistingCredentials = NO;
	}
	if(![password isEqualToString:aPassword])
	{
		[password release];
		password = [aPassword copy];
		haveUsedExistingCredentials = NO;
	}
}

- (NSString *)authenticationRealm
{
	if(auth)
		return [NSMakeCollectable(CFHTTPAuthenticationCopyRealm(auth)) autorelease];
	else
		return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSURL *)url
{
	return [[currentURL retain] autorelease];
}

- (NSString *)filePath
{
	return [[filePath retain] autorelease];
}

- (BOOL)isConnected
{
	return [asyncSocket isConnected];
}

- (NSString *)connectedHost
{
	return [asyncSocket connectedHost];
}

- (UInt16)connectedPort
{
	return [asyncSocket connectedPort];
}

- (BOOL)isConnectedToHost:(NSString *)host port:(UInt16)port
{
	if(![host isEqualToString:[asyncSocket connectedHost]])
	{
		return NO;
	}
	if(port != [asyncSocket connectedPort])
	{
		return NO;
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Progress
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (UInt64)fileSizeInBytes
{
	return fileSizeInBytes;
}

- (UInt64)totalBytesReceived
{
	return totalBytesReceived + progressOfCurrentRead;
}

- (double)progress
{
	if(isProcessingRequestOrResponse && (fileSizeInBytes > 0))
	{
		return ((double)(totalBytesReceived + progressOfCurrentRead)) / ((double)fileSizeInBytes);
	}
	
	return 0.0;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delegate Helper Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)onDownloadDidBegin
{
	if([delegate respondsToSelector:@selector(httpClientDownloadDidBegin:)])
	{
		[delegate httpClientDownloadDidBegin:self];
	}
}

- (void)onDidReceiveDataOfLength:(unsigned)length
{
	if([delegate respondsToSelector:@selector(httpClient:didReceiveDataOfLength:)])
	{
		[delegate httpClient:self didReceiveDataOfLength:length];
	}
}

- (void)onDownloadDidFinish
{
	NSString *downloadedFilePath = [[filePath retain] autorelease];
	
	[self cleanup];
	
	if([delegate respondsToSelector:@selector(httpClient:downloadDidFinish:)])
	{
		[delegate httpClient:self downloadDidFinish:downloadedFilePath];
	}
}

- (void)onDidFailWithError:(NSError *)error
{
	[self cleanup];
	
	if([delegate respondsToSelector:@selector(httpClient:didFailWithError:)])
	{
		[delegate httpClient:self didFailWithError:error];
	}
}

- (void)onDidFailWithStatusCode:(UInt32)statusCode
{
	[self cleanup];
	
	if([delegate respondsToSelector:@selector(httpClient:didFailWithStatusCode:)])
	{
		[delegate httpClient:self didFailWithStatusCode:statusCode];
	}
}

- (void)onDidFailWithAuthenticationChallenge
{
	[self cleanup];
	
	if([delegate respondsToSelector:@selector(httpClient:didFailWithAuthenticationChallenge:)])
	{
		[delegate httpClient:self didFailWithAuthenticationChallenge:auth];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncSocket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called immediately prior to opening up the stream.
 * This is the time to manually configure the stream if necessary.
**/
- (BOOL)onSocketWillConnect:(AsyncSocket *)sock
{
	if([[currentURL scheme] isEqualToString:@"https"])
	{
		// Connecting to a secure server
		NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:2];
		
		// Use the highest possible security
		[settings setObject:(NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL
					 forKey:(NSString *)kCFStreamSSLLevel];
		
		// Allow self-signed certificates (since almost all Mojo clients will be using them)
		[settings setObject:[NSNumber numberWithBool:YES]
					 forKey:(NSString *)kCFStreamSSLAllowsAnyRoot];
		
		[asyncSocket startTLS:settings];
	}
	return YES;
}

/**
 * This method is called after the socket has successfully written all the data to the stream.
**/
- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	// Make sure the tag matches what we wrote,
	// as it's possible the AsyncSocket still had queued writes when we received it.
	
	if(tag == HTTP_HEADERS)
	{
		// Now start reading in the response
		[asyncSocket readDataToData:[AsyncSocket CRLFData]
						withTimeout:READ_FIRST_HEADER_TIMEOUT
								tag:HTTP_HEADERS];
	}
}

/**
 * This method is called after the socket has successfully read data from the stream.
 * Remember that this method will only be called after the socket reaches a CRLF, or after it's read the proper length.
**/
- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData*)data withTag:(long)tag
{
	// Setup method variables
	BOOL downloadComplete = NO;
	
	if(tag == HTTP_HEADERS)
	{
		DDLogVerbose(@"HTTPClient: Received header line");
		
		// Append the data to our http message
		BOOL result = CFHTTPMessageAppendBytes(response, [data bytes], [data length]);
		if(!result)
		{
			DDLogError(@"HTTPClient: Received invalid http header line");
			[asyncSocket disconnect];
		}
		else if(!CFHTTPMessageIsHeaderComplete(response))
		{
			// We don't have a complete header yet
			// That is, we haven't yet received a CRLF on a line by itself, indicating the end of the header
			[asyncSocket readDataToData:[AsyncSocket CRLFData]
							withTimeout:READ_HEADER_TIMEOUT
									tag:HTTP_HEADERS];
		}
		else
		{
			if(DEBUG_VERBOSE)
			{
				NSData *tempData = (NSData *)CFHTTPMessageCopySerializedMessage(response);
				NSString *tempStr = [[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding];
				
				DDLogVerbose(@"HTTPClient: Response:\n%@", tempStr);
				
				[tempStr release];
				[tempData release];
			}
			
			// Extract the http status code
			UInt32 statusCode = CFHTTPMessageGetResponseStatusCode(response);
			
			// Extract the Content-Length and/or Transfer-Encoding so we know how to read the response
			NSString *contentLength, *transferEncoding;
			
			contentLength = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Content-Length"));
			[contentLength autorelease];
			
			if(contentLength)
				fileSizeInBytes = (UInt64)strtoull([contentLength UTF8String], NULL, 10);
			else
				fileSizeInBytes = (UInt64)0;
			
			transferEncoding = (NSString *)CFHTTPMessageCopyHeaderFieldValue(response, CFSTR("Transfer-Encoding"));
			[transferEncoding autorelease];
			
			usingChunkedTransfer = [transferEncoding isEqualToString:@"chunked"];
			
			// Now we decide what to do based on the status code we received...
			if(statusCode == 200)
			{
				if(fileSizeInBytes > 0)
				{
					CFIndex bytesToRead = fileSizeInBytes < READ_CHUNKSIZE ? fileSizeInBytes : READ_CHUNKSIZE;
					
					[asyncSocket readDataToLength:bytesToRead
									  withTimeout:READ_BODY_TIMEOUT 
											  tag:HTTP_BODY];
					
					// Inform the delegate that the download has now begun
					[self onDownloadDidBegin];
				}
				else if(usingChunkedTransfer)
				{
					chunkedTransferStage = CHUNKED_STAGE_SIZE;
					[asyncSocket readDataToData:[AsyncSocket CRLFData]
									withTimeout:READ_CHUNKSIZE_TIMEOUT
											tag:HTTP_BODY_CHUNKED];
					
					// Inform the delegate that the download has now begun
					[self onDownloadDidBegin];
				}
				else
				{
					// We got an OK status code, but the server sent a malformed response
					// Nothing else to do here, since we can't trust the server anymore
					
					[self onDidFailWithStatusCode:statusCode];
				}
			}
			else if(statusCode == 401)
			{
				// Release any previous authentication that may be stored
				if(auth)
				{
					CFRelease(auth);
					auth = nil;
				}
				
				// Create an authentication object from the given response
				// We'll use this to continually provide the proper authentication for each subsequent request
				
				// There is a bug nestled in CFHTTPAuthenticationCreateFromResponse method
				// Essentially, it calls CFHTTPMessageCopyURL and passes it the response
				// Of course, there is no URL request in the response, and the method causes a crash (brilliant)
				// This is a known bug, and has already been reported to Apple.
				// The only known workaround is to directly set the request URL in the response.
				NSURL *requestURL = [(NSURL *)CFHTTPMessageCopyRequestURL(request) autorelease];
				_CFHTTPMessageSetResponseURL(response, (CFURLRef)requestURL);
				
				auth = CFHTTPAuthenticationCreateFromResponse(kCFAllocatorDefault, response);
				
				// Some servers may send a human readable HTML message along with their 401 status code.
				if(fileSizeInBytes > 0)
				{
					// We have to finish reading in the response, even though we know we're going to ignore it
					// If we don't it won't get flushed from our socket read buffer
					CFIndex bytesToRead = fileSizeInBytes < READ_CHUNKSIZE ? fileSizeInBytes : READ_CHUNKSIZE;
					
					[asyncSocket readDataToLength:bytesToRead
									  withTimeout:READ_BODY_TIMEOUT
											  tag:HTTP_BODY_IGNORE];
				}
				else if(usingChunkedTransfer)
				{
					// We have to finish reading in the response, even though we know we're going to ignore it
					// If we don't it won't get flushed from our socket read buffer
					chunkedTransferStage = CHUNKED_STAGE_SIZE;
					[asyncSocket readDataToData:[AsyncSocket CRLFData]
									withTimeout:READ_CHUNKSIZE_TIMEOUT
											tag:HTTP_BODY_CHUNKED_IGNORE];
				}
				else
				{
					if(username && password && !haveUsedExistingCredentials)
					{
						// We have an existing username and password that we haven't tried yet
						[self sendRequest];
					}
					else
					{
						[self onDidFailWithAuthenticationChallenge];
					}
				}
			}
			else
			{
				// The http server returned a status code other than 'OK', or "Unauthorized"
				// This means there was some sort of unexpected problem
				
				// Some servers may send a human readable HTML message along with their error status code.
				if(fileSizeInBytes > 0)
				{
					// We have to finish reading in the response, even though we know we're going to ignore it
					// If we don't it won't get flushed from our socket read buffer
					CFIndex bytesToRead = fileSizeInBytes < READ_CHUNKSIZE ? fileSizeInBytes : READ_CHUNKSIZE;
					
					[asyncSocket readDataToLength:bytesToRead
									  withTimeout:READ_BODY_TIMEOUT
											  tag:HTTP_BODY_IGNORE];
				}
				else if(usingChunkedTransfer)
				{
					// We have to finish reading in the response, even though we know we're going to ignore it
					// If we don't it won't get flushed from our socket read buffer
					chunkedTransferStage = CHUNKED_STAGE_SIZE;
					[asyncSocket readDataToData:[AsyncSocket CRLFData]
									withTimeout:READ_CHUNKSIZE_TIMEOUT
											tag:HTTP_BODY_CHUNKED_IGNORE];
				}
				else
				{
					[self onDidFailWithStatusCode:statusCode];
				}
			}
		}
	}
	else if(tag == HTTP_BODY || tag == HTTP_BODY_IGNORE)
	{
		progressOfCurrentRead = 0;
		totalBytesReceived += [data length];
		
		DDLogVerbose(@"HTTPClient: totalBytesReceived:%qu progress:%f" , totalBytesReceived, [self progress]);
		
		if(tag == HTTP_BODY)
		{
			[file writeData:data];
		}
		
		// Check to see if the download is complete
		downloadComplete = totalBytesReceived == fileSizeInBytes;
		
		if(!downloadComplete)
		{
			UInt64 bytesLeft = fileSizeInBytes - totalBytesReceived;
			CFIndex bytesToRead = bytesLeft < READ_CHUNKSIZE ? bytesLeft : READ_CHUNKSIZE;
			
			[asyncSocket readDataToLength:bytesToRead
							  withTimeout:READ_BODY_TIMEOUT 
									  tag:tag];
		}
	}
	else if(tag == HTTP_BODY_CHUNKED || tag == HTTP_BODY_CHUNKED_IGNORE)
	{
		if(chunkedTransferStage == CHUNKED_STAGE_SIZE)
		{
			// We have just read in a line with the size of the chunk data, in hex, 
			// possibly followed by a semicolon and extra parameters that can be ignored,
			// and ending with CRLF.
			NSString *sizeLine = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
			
			chunkSizeInBytes = strtoull([sizeLine UTF8String], NULL, 16);
			
			if(chunkSizeInBytes > 0)
			{
				chunkedTransferStage = CHUNKED_STAGE_DATA;
				
				// Don't forget about the trailing CRLF when downloading the data
				chunkSizeInBytes += 2;
				
				// Reset how much we've received for the current chunk
				totalChunkReceived = 0;
				
				CFIndex bytesToRead = chunkSizeInBytes < READ_CHUNKSIZE ? chunkSizeInBytes : READ_CHUNKSIZE;
				
				[asyncSocket readDataToLength:bytesToRead
								  withTimeout:READ_BODY_TIMEOUT
										  tag:tag];
			}
			else
			{
				chunkedTransferStage = CHUNKED_STAGE_FOOTER;
				[asyncSocket readDataToData:[AsyncSocket CRLFData]
								withTimeout:READ_FOOTER_TIMEOUT
										tag:tag];
			}
		}
		else if(chunkedTransferStage == CHUNKED_STAGE_DATA)
		{
			totalChunkReceived += [data length];
			
			if(tag == HTTP_BODY_CHUNKED)
			{
				// Write the data to file, but be sure not to include the trailing CRLF
				if(totalChunkReceived <= (chunkSizeInBytes - 2))
				{
					[file writeData:data];
				}
				else
				{
					NSUInteger overflow = totalChunkReceived - chunkSizeInBytes + 2;
					NSUInteger dataLength = [data length] - overflow;
					
					NSData *dataMinusBookkeeping = [NSData dataWithBytesNoCopy:(void *)[data bytes]
																		length:dataLength
																  freeWhenDone:NO];
					[file writeData:dataMinusBookkeeping];
				}
			}
			
			// Check to see if the download of the current chunk is complete
			BOOL chunkDownloadComplete = totalChunkReceived == chunkSizeInBytes;
			
			if(chunkDownloadComplete)
			{
				chunkedTransferStage = CHUNKED_STAGE_SIZE;
				[asyncSocket readDataToData:[AsyncSocket CRLFData]
								withTimeout:READ_CHUNKSIZE_TIMEOUT
										tag:tag];
			}
			else
			{
				UInt64 bytesLeft = chunkSizeInBytes - totalChunkReceived;
				CFIndex bytesToRead = bytesLeft < READ_CHUNKSIZE ? bytesLeft : READ_CHUNKSIZE;
				
				[asyncSocket readDataToLength:bytesToRead
								  withTimeout:READ_BODY_TIMEOUT
										  tag:tag];
			}
		}
		else if(chunkedTransferStage == CHUNKED_STAGE_FOOTER)
		{
			// The data we just downloaded is either a footer, or a empty line (single CRLF)
			if([data length] > 2)
			{
				// We currently don't care about footers, because we're not going to be using them for anything
				// If we did care about them, we could parse them out (ignoring the trailing CRLF),
				// and use CFHTTPMessageSetHeaderFieldValue to add them to the header.
				[asyncSocket readDataToData:[AsyncSocket CRLFData] 
								withTimeout:READ_FOOTER_TIMEOUT 
										tag:tag];
			}
			else
			{
				// Mark the download as complete
				// We take care of notifying the delegate and cleaning up below
				downloadComplete = YES;
			}
		}
	}
	
	// If our download is complete, we need to inform our delegate
	if(downloadComplete)
	{
		if(tag == HTTP_BODY || tag == HTTP_BODY_CHUNKED)
		{
			// Make sure the file is finished writing
			[file synchronizeFile];
			
			[self onDownloadDidFinish];
		}
		else
		{
			// We were forced to read in the response body even though we didn't care about it
			// We had to do this to properly flush the socket read buffer
			
			// Extract the http status code
			UInt32 statusCode = CFHTTPMessageGetResponseStatusCode(response);
			
			if(statusCode == 401)
			{
				if(username && password && !haveUsedExistingCredentials)
				{
					// We have an existing username and password that we haven't tried yet
					[self sendRequest];
				}
				else
				{
					[self onDidFailWithAuthenticationChallenge];
				}
			}
			else
			{
				[self onDidFailWithStatusCode:statusCode];
			}
		}
	}
}

- (void)onSocket:(AsyncSocket *)sock didReadPartialDataOfLength:(CFIndex)partialLength tag:(long)tag
{
	if(tag == HTTP_BODY)
	{
		progressOfCurrentRead += partialLength;
		
		[self onDidReceiveDataOfLength:(unsigned)partialLength];
	}
	
	// We don't bother to report the progress when using chunked transfer-encoding
	// because we don't know how many chunks will be sent,
	// so the delegate wouldn't be able to display a progress bar anyways.
}

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err
{
	DDLogVerbose(@"HTTPClient: onSocket:willDisconnectWithError:");
	
	// Some kind of error occurred
	// This is not a status code error, but some other (worse) error that will require a standard error message
	if(isProcessingRequestOrResponse)
	{
		[self onDidFailWithError:err];
	}
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	DDLogVerbose(@"HTTPClient: onSocketDidDisconnect:");
}

@end
