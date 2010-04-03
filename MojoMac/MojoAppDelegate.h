#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "HelperProtocol.h"
#import "MojoProtocol.h"

@class PreferencesController;

#define HelperProxyReadyNotification    @"HelperProxyReady"
#define HelperProxyClosingNotification  @"HelperProxyClosing"


@interface MojoAppDelegate : AppDelegate
{
	NSDistantObject <HelperProtocol> *helperProxy;
	NSObject <MojoProtocol> *mojoRootObject;
	
    IBOutlet id aboutController;
    IBOutlet id preferencesController;
    IBOutlet id serviceListController;
    IBOutlet id serviceListWindow;
}
- (NSString *)applicationTemporaryDirectory;
- (NSDistantObject <HelperProtocol> *)helperProxy;

- (int)serverPortNumber;
- (PreferencesController *)preferencesController;

- (NSString *)getCountStr:(int)numSongs;
- (NSString *)getDurationStr:(uint64_t)totalTime longView:(BOOL)longView;
- (NSString *)getSizeStr:(uint64_t)totalSize;

- (IBAction)mojoHelp:(id)sender;

@end
