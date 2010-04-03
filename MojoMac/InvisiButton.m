#import "InvisiButton.h"

@implementation InvisiButton

/**
 * For the life of me I can't figure out how to prevent a button from goofing up the LCDView when it's pushed.
 * I've tried setting
 * [[button cell] setShowsStateBy:NSNoCellMask] and [[button cell] setHighlightsBy:NSNoCellMask],
 * along with hundreds of various types of buttons, all with no success.
 *
 * Completely fed up, I've decided to create my own button class
 * that overrides the mouseDown method to prevent any drawing at all.
**/
- (void)mouseDown:(NSEvent *)theEvent
{
	if([self image] && [self alternateImage])
	{
		// Swap image and alternate image in order to display the alternate image
		NSImage *temp = [self image];
		[self setImage:[self alternateImage]];
		[self setAlternateImage:temp];
		
		// Redraw the button - which will screw up the LCDView (superview), so redraw that as well
		[self setNeedsDisplay:YES];
		[[self superview] setNeedsDisplay:YES];
	}
}

- (void)mouseUp:(NSEvent *)theEvent
{
	if([self image] && [self alternateImage])
	{
		// Swap image and alternate image back to original position and display original image again
		NSImage *temp = [self image];
		[self setImage:[self alternateImage]];
		[self setAlternateImage:temp];
		
		// Redraw the button - which will screw up the LCDView (superview), so redraw that as well
		[self setNeedsDisplay:YES];
		[[self superview] setNeedsDisplay:YES];
	}
	
	// Invoke any needed methods since the button has now fired
	[[self target] performSelector:[self action] withObject:self];
}

@end
