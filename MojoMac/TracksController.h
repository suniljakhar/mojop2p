#import <Cocoa/Cocoa.h>


@interface TracksController : NSArrayController
{
	NSString *searchString;
}

- (NSString *)searchString;
- (void)setSearchString:(NSString *)newSearchString;

@end
