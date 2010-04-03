#import <Cocoa/Cocoa.h>


@protocol DDButtonCell

- (int)numberOfButtons;
- (NSRect)button:(int)index rectForBounds:(NSRect)theRect;

@end
