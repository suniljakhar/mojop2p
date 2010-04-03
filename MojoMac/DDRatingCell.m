#import "DDRatingCell.h"


@implementation DDRatingCell

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	[self setIntValue:([self intValue] / 20)];
	
	if([self isHighlighted])
	{
		NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
		
		if([highlightColor isEqual:[NSColor alternateSelectedControlColor]])
			[self setImage:[NSImage imageNamed:@"whiteStar.png"]];
		else
			[self setImage:nil];
	}
	else
	{
		[self setImage:nil];
	}
	
	// We indent the frame 6 pixels
	// It looks better this way, and matches iTunes
	cellFrame.size.width -= 6;
	cellFrame.origin.x += 6;
	
	[super drawWithFrame:cellFrame inView:controlView];
}

@end
