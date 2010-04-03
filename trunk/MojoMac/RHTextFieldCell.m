#import "RHTextFieldCell.h"


@implementation RHTextFieldCell

/**
 * Overriden to center the content of the text field cell.
**/
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSSize contentSize = [self cellSize];
    cellFrame.origin.y += (cellFrame.size.height - contentSize.height) / 2.0F;
    cellFrame.size.height = contentSize.height;
	
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end
