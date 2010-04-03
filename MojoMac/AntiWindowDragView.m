#import "AntiWindowDragView.h"

@implementation AntiWindowDragView

- (id)initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
	{
		// Add initialization code here
	}
	return self;
}

- (void)drawRect:(NSRect)rect
{
}

- (BOOL)isOpaque
{
	return YES;
}

@end
