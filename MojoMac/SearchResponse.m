#import "SearchResponse.h"
#import "HTTPConnection.h"
#import "ITunesSearch.h"


@implementation SearchResponse

- (id)initWithQuery:(NSDictionary *)query forConnection:(HTTPConnection *)parent runLoopModes:(NSArray *)modes
{
	if((self = [super init]))
	{
		connection = parent; // Parents retain children, children do NOT retain parents
		
		connectionThread = [[NSThread currentThread] retain];
		connectionRunLoopModes = [modes copy];
		
		responseData = nil;
		responseOffset = 0;
		
		[NSThread detachNewThreadSelector:@selector(search:) toTarget:self withObject:query];
	}
	return self;
}

- (void)dealloc
{
	[connectionThread release];
	[connectionRunLoopModes release];
	[responseData release];
	[super dealloc];
}

- (UInt64)contentLength
{
	// This method shouldn't be called because we're using chunked transfer encoding
	return 0;
}

- (UInt64)offset
{
	return responseOffset;
}

- (void)setOffset:(UInt64)offset
{
	responseOffset = offset;
}

- (NSData *)readDataOfLength:(unsigned int)lengthParameter
{
	unsigned int remaining = [responseData length] - responseOffset;
	unsigned int length = lengthParameter < remaining ? lengthParameter : remaining;
	
	void *bytes = (void *)([responseData bytes] + responseOffset);
	
	responseOffset += length;
	
	return [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:NO];
}

- (BOOL)isDone
{
	return (responseOffset == [responseData length]);
}

- (BOOL)isAsynchronous
{
	return YES;
}

- (BOOL)isChunked
{
	return YES;
}

- (void)connectionDidClose
{
	// Prevent any further calls to the connection
	connection = nil;
}

- (void)search:(NSDictionary *)query
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	ITunesSearch *search = [[[ITunesSearch alloc] initWithSearchQuery:query] autorelease];
	
	NSString *errorString = nil;
	responseData = [[NSPropertyListSerialization dataFromPropertyList:[search matchingTracks]
															   format:NSPropertyListXMLFormat_v1_0
													 errorDescription:&errorString] retain];
	
	if(responseData == nil)
	{
		NSLog(@"SearchResponse: NSPropertyListSerializationError: %@", errorString);
		
		responseData = [[@"error" dataUsingEncoding:NSUTF8StringEncoding] retain];
	}
	
	[self performSelector:@selector(searchDidFinish)
				 onThread:connectionThread
			   withObject:nil
			waitUntilDone:NO
					modes:connectionRunLoopModes];
	
	[pool release];
}

- (void)searchDidFinish
{
	[connection responseHasAvailableData];
}

@end
