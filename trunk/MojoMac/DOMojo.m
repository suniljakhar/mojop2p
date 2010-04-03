#import "DOMojo.h"


@implementation DOMojo

/**
 * This method allows the MojoHelper to post notifications within Mojo.
 * This method is preferred since it's less expensive than an NSDitributedNotification.
**/
- (void)postNotificationWithName:(NSString *)name
{
	[[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
}

@end
