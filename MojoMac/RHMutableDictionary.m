#import "RHMutableDictionary.h"


@implementation NSMutableDictionary (RHMutableDictionary)

+ (id)dictionaryWithData:(NSData *)data
{
	return [[[NSMutableDictionary alloc] initWithData:data] autorelease];
}

- (id)initWithData:(NSData *)data
{
	// No need to release self first before reassigning it
	// This is because [NSMutableDictionary alloc] returns a static NSPlaceHolderDictionary
	
	self = (NSMutableDictionary *)
	[NSPropertyListSerialization propertyListFromData:data
									 mutabilityOption:NSPropertyListMutableContainers
											   format:NULL
									 errorDescription:nil];
	return [self retain];
}

@end
