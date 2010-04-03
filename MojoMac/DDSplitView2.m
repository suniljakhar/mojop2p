#import "DDSplitView2.h"


@implementation DDSplitView2

- (void)awakeFromNib
{
	bgImage = [[NSImage imageNamed:@"metalColumnDivider.png"] retain];
	[bgImage setFlipped:YES];
}

- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
    [bgImage release];
    [super dealloc];
}

- (CGFloat)dividerThickness
{
	return 8;
}

- (void)drawDividerInRect:(NSRect)rect
{
	// Draw metalBg image, covering the entire frame
	[bgImage drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
}

@end
