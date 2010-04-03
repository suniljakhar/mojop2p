#import "ToggleTextField.h"

/**
 * A ToggleTextField is a text field that fires when it's clicked (on mouseDown:).
 * This allows the text field to toggle between displaying various strings.
**/
@implementation ToggleTextField

- (void)mouseDown:(NSEvent *)theEvent
{
	[[self target] performSelector:[self action] withObject:self];
	[[self superview] setNeedsDisplay:YES];
}

@end
