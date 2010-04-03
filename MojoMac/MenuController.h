#import <Cocoa/Cocoa.h>

@interface MenuController : NSObject
{
	// The status item to go in the status bar
	NSStatusItem *statusItem;
	
	// Interface Builder outlets
    IBOutlet id menu;
}

- (void)displayMenuItem;
- (void)hideMenuItem;

- (IBAction)connect:(id)sender;
- (IBAction)openMojo:(id)sender;
- (IBAction)preferences:(id)sender;
- (IBAction)quit:(id)sender;
@end
