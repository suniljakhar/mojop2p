#import "SrcTableCornerView.h"


@implementation SrcTableCornerView

- (id)initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame]))
	{
		metalBg = [[NSImage imageNamed:@"metalColumnHeader.png"] retain];
		[metalBg setFlipped:YES];
	}
	return self;
}

- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
    [metalBg release];
    [super dealloc];
}

- (void)drawRect:(NSRect)rect
{
	// Draw metalBg image, covering the entire frame
	[metalBg drawInRect:rect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
}

@end
