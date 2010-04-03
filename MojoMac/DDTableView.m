#import "DDTableView.h"
#import "DDButtonCell.h"

// RGB values for stripe color (light green)
#define STRIPE_RED   (228.0F / 255.0F)
#define STRIPE_GREEN (238.0F / 255.0F)
#define STRIPE_BLUE  (233.0F / 255.0F)

@implementation DDTableView

static NSColor *stripeColor;

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		
		stripeColor = [[NSColor colorWithCalibratedRed:STRIPE_RED
												 green:STRIPE_GREEN
												  blue:STRIPE_BLUE
												 alpha:1.0F] retain];
	}
}

- (id)init
{
	if((self = [super init]))
	{
		clickedPointInTable = NSMakePoint(0, 0);
	}
	return self;
}

- (id)initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
	{
		clickedPointInTable = NSMakePoint(0, 0);
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if((self = [super initWithCoder:aDecoder]))
	{
		clickedPointInTable = NSMakePoint(0, 0);
	}
	return self;
}

- (NSPoint)clickedPointInTable
{
	return clickedPointInTable;
}

- (void)mouseDown:(NSEvent *)event
{
	clickedPointInTable = [self convertPoint:[event locationInWindow] fromView:nil];
	
	clickedRowIndex = [self rowAtPoint:clickedPointInTable];
	clickedColumnIndex = [self columnAtPoint:clickedPointInTable];
	
	NSTableColumn *tableColumn = [[self tableColumns] objectAtIndex:clickedColumnIndex];
	
	id dataCell = [tableColumn dataCellForRow:clickedRowIndex];
	
	if([dataCell conformsToProtocol:@protocol(DDButtonCell)])
	{
		NSRect cellRect = [self frameOfCellAtColumn:clickedColumnIndex row:clickedRowIndex];
		
		int numberOfButtons = [dataCell numberOfButtons];
		
		int i;
		for(i = 0; i < numberOfButtons; i++)
		{
			NSRect cellButtonRect = [dataCell button:i rectForBounds:cellRect];
			
			if(NSPointInRect(clickedPointInTable, cellButtonRect))
			{
				// Mouse down in cell button
								
				clickedButtonIndex = i;
				
				[self setNeedsDisplayInRect:[self frameOfCellAtColumn:clickedColumnIndex row:clickedRowIndex]];
				
				handledMouseDown = YES;
				return;
			}
		}
	}
    
	handledMouseDown = NO;
    [super mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
	clickedPointInTable = NSMakePoint(0, 0);
	
	if(handledMouseDown)
	{
		NSPoint pointInTable = [self convertPoint:[event locationInWindow] fromView:nil];
		
		int upRowIndex = [self rowAtPoint:pointInTable];
		int upColumnIndex = [self columnAtPoint:pointInTable];
		
		NSTableColumn *clickedTableColumn = [[self tableColumns] objectAtIndex:clickedColumnIndex];
		
		id dataCell = [clickedTableColumn dataCellForRow:clickedRowIndex];
		
		if((clickedColumnIndex == upColumnIndex) && (clickedRowIndex == upRowIndex))
		{
			NSRect cellRect = [self frameOfCellAtColumn:upColumnIndex row:upRowIndex];
			
			NSRect cellButtonRect = [dataCell button:clickedButtonIndex rectForBounds:cellRect];
			
			if(NSPointInRect(pointInTable, cellButtonRect))
			{
				// Mouse down and up in same row, column and button
				
				if([[self delegate] respondsToSelector:@selector(tableView:didClickButton:atTableColumn:row:)])
				{
					[[self delegate] tableView:self
					            didClickButton:clickedButtonIndex
					             atTableColumn:clickedTableColumn
					                       row:clickedRowIndex];
				}
			}
		}
		
		[self setNeedsDisplayInRect:[self frameOfCellAtColumn:clickedColumnIndex row:clickedRowIndex]];
		return;
	}
    
    [super mouseUp:event];
}

/**
 * This routine does the actual blue stripe drawing, filling in every other row of the table
 * with a blue background so you can follow the rows easier with your eyes.
**/
- (void)drawStripesInRect:(NSRect)clipRect
{
	float fullRowHeight = [self rowHeight] + [self intercellSpacing].height;
	float clipBottom = NSMaxY(clipRect);
	
	int firstStripe = clipRect.origin.y / fullRowHeight;
	
	if(firstStripe % 2 == 0)
	{
		// We're only interested in drawing the stripes
		firstStripe++;
	}
	
	// Set up first rect
	NSRect stripeRect;
	stripeRect.origin.x = clipRect.origin.x;
	stripeRect.origin.y = firstStripe * fullRowHeight;
	stripeRect.size.width = clipRect.size.width;
	stripeRect.size.height = fullRowHeight;
	
	// Set color
	[stripeColor set];
	
	// And draw the stripes
	while(stripeRect.origin.y < clipBottom)
	{
		NSRectFill(stripeRect);
		stripeRect.origin.y += fullRowHeight * 2.0F;
	}
}

/**
 * This is called after the table background is filled in, but before the cell contents are drawn.
 * We override it so we can do our own light-blue row stripes a la iTunes.
**/
- (void)highlightSelectionInClipRect:(NSRect)rect
{
    [self drawStripesInRect:rect];
    [super highlightSelectionInClipRect:rect];
}

@end
