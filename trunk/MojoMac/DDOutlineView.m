#import "DDOutlineView.h"
#import "DDButtonCell.h"


@implementation DDOutlineView

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
	if(![self isEnabled])
	{
		[super mouseDown:event];
		return;
	}
	
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
		for(i = 0; i < numberOfButtons && !handledMouseDown; i++)
		{
			NSRect cellButtonRect = [dataCell button:i rectForBounds:cellRect];
			
			if(NSPointInRect(clickedPointInTable, cellButtonRect))
			{
				// Mouse down in cell button
				
				clickedButtonIndex = i;
				
				[self selectRowIndexes:[NSIndexSet indexSetWithIndex:clickedRowIndex] byExtendingSelection:NO];
				
				handledMouseDown = YES;
				return;
			}
		}
	}
    
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
				
				if([[self delegate] respondsToSelector:@selector(outlineView:didClickButton:atTableColumn:row:)])
				{
					[[self delegate] outlineView:self
								  didClickButton:clickedButtonIndex
								   atTableColumn:clickedTableColumn
											 row:clickedRowIndex];
				}
			}
		}
		
		[self setNeedsDisplayInRect:[self frameOfCellAtColumn:clickedColumnIndex row:clickedRowIndex]];
	}
    
	handledMouseDown = NO;
    [super mouseUp:event];
}

@end
