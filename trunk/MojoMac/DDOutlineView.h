#import <Cocoa/Cocoa.h>


@interface DDOutlineView : NSOutlineView
{
	NSPoint clickedPointInTable;
	int clickedRowIndex;
	int clickedColumnIndex;
	int clickedButtonIndex;
	BOOL handledMouseDown;
}

- (NSPoint)clickedPointInTable;

@end

@interface NSObject (DDTableViewDelegate)

- (void)outlineView:(NSOutlineView *)anOutlineView
   didClickButton:(int)buttonIndex
	atTableColumn:(NSTableColumn *)aTableColumn
			  row:(int)rowIndex;

@end
