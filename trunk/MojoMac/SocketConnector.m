#import "SocketConnector.h"
#import "AsyncSocket.h"

#import <sys/socket.h>

#define PREFER_IPV4 1


@implementation SocketConnector

- (id)initWithAddresses:(NSArray *)addresses
{
	if((self = [super init]))
	{
		// Sort the addresses.
		// We put the IPv4 addresses first, and the IPv6 addresses last.
		// We do this because IPv4 is still more prevalent (unfortunately), and is more likely to succeed.
		
		NSMutableArray *sortedArray = [NSMutableArray arrayWithCapacity:[addresses count]];
		
		NSUInteger i;
		for(i = 0; i < [addresses count]; i++)
		{
			struct sockaddr *sa = (struct sockaddr *)[[addresses objectAtIndex:i] bytes];
			
			if(sa->sa_family == AF_INET)
			{
				#if PREFER_IPV4
					// Prefer IPv4
					[sortedArray insertObject:[addresses objectAtIndex:i] atIndex:0];
				#else
					// Prefer IPv6
					[sortedArray addObject:[addresses objectAtIndex:i]];
				#endif
			}
			else if(sa->sa_family == AF_INET6)
			{
				#if PREFER_IPV4
					// Prefer IPv4
					[sortedArray addObject:[addresses objectAtIndex:i]];
				#else
					// Prefer IPv6
					[sortedArray insertObject:[addresses objectAtIndex:i] atIndex:0];
				#endif
			}
		}
		
		sortedAddresses = [sortedArray copy];
	}
	return self;
}

- (void)dealloc
{
	[tag release];
	[sortedAddresses release];
	
	if([asyncSocket delegate] == self)
	{
		[asyncSocket setDelegate:nil];
	}
	[asyncSocket release];
	
	[super dealloc];
}

- (NSObject *)tag
{
	return tag;
}

- (void)setTag:(NSObject *)newTag
{
	[tag autorelease];
	tag = [newTag retain];
}

- (void)start:(id)theDelegate
{
	if(asyncSocket != nil)
	{
		// We've already started
		return;
	}
	
	delegate = theDelegate;
	
	asyncSocket = [[AsyncSocket alloc] initWithDelegate:self];
	
	long index = 0;
	BOOL done = NO;
	
	while((index < [sortedAddresses count]) && !done)
	{
		[asyncSocket setUserData:index];
		
		if([asyncSocket connectToAddress:[sortedAddresses objectAtIndex:index] error:nil])
		{
			done = YES;
		}
		else
		{
			index++;
		}
	}
	
	if(!done)
	{
		// We either didn't have any addresses to try, or they all immediately failed!
		// Invoke the delegate method, but not from within this method.
		if([delegate respondsToSelector:@selector(socketConnectorDidNotConnect:)])
		{
			[delegate performSelector:@selector(socketConnectorDidNotConnect:) withObject:self afterDelay:0];
		}
	}
}

- (void)abort
{
	if([asyncSocket delegate] == self)
	{
		[asyncSocket setDelegate:nil];
	}
	[asyncSocket release];
	asyncSocket = nil;
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
	long index = [sock userData] + 1;
	BOOL done = NO;
	
	while((index < [sortedAddresses count]) && !done)
	{
		[asyncSocket setUserData:index];
		
		if([asyncSocket connectToAddress:[sortedAddresses objectAtIndex:index] error:nil])
		{
			done = YES;
		}
		else
		{
			index++;
		}
	}
	
	if(!done)
	{
		if([delegate respondsToSelector:@selector(socketConnectorDidNotConnect:)])
		{
			[delegate socketConnectorDidNotConnect:self];
		}
	}
}

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	[asyncSocket setDelegate:nil];
	
	if([delegate respondsToSelector:@selector(socketConnector:didConnect:)])
	{
		[delegate socketConnector:self didConnect:asyncSocket];
	}
}

@end
