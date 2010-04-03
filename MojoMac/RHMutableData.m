#import "RHMutableData.h"


@implementation NSMutableData (RHMutableData)

- (void)trimStart:(NSUInteger)length
{
	[self replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
}

- (void)trimEnd:(NSUInteger)length
{
	[self replaceBytesInRange:NSMakeRange([self length] - length, length) withBytes:NULL length:0];
}

- (NSString *)stringValue
{
	return [self stringValueWithEncoding:NSUTF8StringEncoding];
}

- (NSString *)stringValueWithRange:(NSRange)subrange
{
	return [self stringValueWithRange:subrange encoding:NSUTF8StringEncoding];
}

- (NSString *)stringValueWithEncoding:(NSStringEncoding)encoding
{
	NSString *result = [[NSString alloc] initWithData:self encoding:encoding];
	return [result autorelease];
}

- (NSString *)stringValueWithRange:(NSRange)subrange encoding:(NSStringEncoding)encoding
{
	if(subrange.location == 0 && subrange.length == [self length])
	{
		return [self stringValueWithEncoding:encoding];
	}
	else
	{
		void *bytes = [self mutableBytes];
		void *subbytes = bytes + subrange.location;
		
		NSData *subdata = [NSData dataWithBytesNoCopy:subbytes length:subrange.length freeWhenDone:NO];
		
		NSString *result = [[NSString alloc] initWithData:subdata encoding:encoding];
		return [result autorelease];
	}
}

- (NSRange)rangeOfData:(NSData *)data
{
	BOOL found = NO;
	
	NSUInteger i = 0;
	while(i < [self length] && !found)
	{
		if(memcmp([self mutableBytes] + i, [data bytes], (size_t)[data length]) == 0)
			found = YES;
		else
			i++;
	}
	
	if(found)
		return NSMakeRange(i, [data length]);
	else
		return NSMakeRange(0, 0);
}

@end
