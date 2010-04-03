#import "RHPanel.h"


@implementation RHPanel

/**
 * This method overrides NSWindow's sendEvent: method.
 * We use it to prevent an Enter in a table cell to cause the selection to move to the next row.
 * 
 * NSWindow's Documentation:
 * This action method dispatches mouse and keyboard events, specified by theEvent,
 * sent to the receiver by the NSApplication object.
**/
- (void)sendEvent:(NSEvent *)event
{
	// If the user pressed a key on the keyboard
    if([event type] == NSKeyDown)
	{
		// Get the character the user pressed
        NSString *s = [event charactersIgnoringModifiers];
        unichar c = [s characterAtIndex:0];
		
		// If they pressed a Return, Enter, or Tab...
		if(c == CCodeReturn || c == CCodeEnter || c == CCodeTab)
		{
			// Now we want to see if the key was pressed in a textfield inside a table view
			// If so, this is the behavior we want to tweak
			
			id text = [self firstResponder];
			if([text isKindOfClass:[NSText class]])
			{
				id tableView = [text delegate];
				if([tableView isKindOfClass:[NSTableView class]])
				{
					[self makeFirstResponder:tableView];
					return;
				}
			}
        }
    }
    [super sendEvent:event];
}

@end
