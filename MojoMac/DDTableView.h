#import <Cocoa/Cocoa.h>

@interface DDTableView : NSTableView
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

- (void)tableView:(NSTableView *)aTableView
   didClickButton:(int)buttonIndex
	atTableColumn:(NSTableColumn *)aTableColumn
			  row:(int)rowIndex;

@end
