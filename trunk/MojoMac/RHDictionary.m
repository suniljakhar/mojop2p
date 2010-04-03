#import "RHDictionary.h"


@implementation NSDictionary (RHDictionary)

+ (id)dictionaryWithData:(NSData *)data
{
	return [[[NSDictionary alloc] initWithData:data] autorelease];
}

- (id)initWithData:(NSData *)data
{
	// No need to release self first before reassigning it
	// This is because [NSDictionary alloc] returns a static NSPlaceHolderDictionary
	
	self = (NSDictionary *)
	[NSPropertyListSerialization propertyListFromData:data
									 mutabilityOption:NSPropertyListImmutable
											   format:NULL
									 errorDescription:nil];
	return [self retain];
}

@end
