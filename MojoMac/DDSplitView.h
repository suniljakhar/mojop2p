#import <Cocoa/Cocoa.h>


@interface DDSplitView : NSSplitView
{
	NSTimer *animationTimer;
}

- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex
                                 withAnimationDuration:(NSTimeInterval)duration;

- (void)collapseSubview:(NSView *)subview;
- (void)collapseSubview:(NSView *)subview withAnimationDuration:(NSTimeInterval)duration;

- (void)uncollapseSubview:(NSView *)subview;
- (void)uncollapseSubview:(NSView *)subview withAnimationDuration:(NSTimeInterval)duration;

@end
