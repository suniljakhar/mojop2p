#import <Cocoa/Cocoa.h>


@interface PlaylistsController : NSTreeController

- (void)setSelectedObjects:(NSArray *)newSelectedObjects;
- (NSIndexPath *)indexPathToObject:(id)object;

@end
