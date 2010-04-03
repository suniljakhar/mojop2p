#import "LCDView.h"

@implementation LCDView

- (id)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect]) != nil) {
		// Add initialization code here
	}
	return self;
}

- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
	[super dealloc];
}

- (BOOL)isOpaque
{
	// This must return NO because the corners are rounded and use transparent pixels
	return NO;
}

- (void)drawRect:(NSRect)rect
{
	NSImage *lcdLeft    = [NSImage imageNamed:@"lcdLeft.png"];
	NSImage *lcdMiddle  = [NSImage imageNamed:@"lcdMiddle.png"];
	NSImage *lcdRight   = [NSImage imageNamed:@"lcdRight.png"];
	
	NSSize lcdLeftSize  = [lcdLeft size];
	NSSize lcdRightSize = [lcdRight size];
	
	[lcdLeft drawAtPoint:NSMakePoint(0,0)
				fromRect:NSZeroRect
			   operation:NSCompositeSourceOver
				fraction:1];
	
	NSRect lcdMiddleRect = NSMakeRect(lcdLeftSize.width, 0,
									  rect.size.width - lcdLeftSize.width - lcdRightSize.width, rect.size.height);
	
	[lcdMiddle drawInRect:lcdMiddleRect
				 fromRect:NSZeroRect
				operation:NSCompositeSourceOver
				 fraction:1];
	
	[lcdRight drawAtPoint:NSMakePoint(rect.size.width - [lcdRight size].width, 0)
				 fromRect:NSZeroRect
				operation:NSCompositeSourceOver
				 fraction:1];
}

@end
