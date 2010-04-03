#import <Cocoa/Cocoa.h>
#import <Growl/Growl.h>
#import "AppDelegate.h"
#import "HelperProtocol.h"
#import "MojoProtocol.h"

@class TCMPortMapping;

#define MojoConnectionDidInitializeNotification @"MojoConnectionDidInitializeNotification"
#define MojoConnectionDidDieNotification        @"MojoConnectionDidDieNotification"


@interface HelperAppDelegate : AppDelegate <GrowlApplicationBridgeDelegate>
{
	NSObject <HelperProtocol> *helper;
	NSDistantObject <MojoProtocol> *mojoProxy;
	
	// Note: helper is an IBOutlet
	
	int serverPortMappingCount;
	TCMPortMapping *serverPortMapping;
	
	BOOL isStartingApp;
	BOOL isGoingToSleep;
	BOOL isWakingFromSleep;
	
	NSString *lastFoundServiceName;
	
	IBOutlet id iTunesLibraryNotFoundWarningPanel;
}

- (NSString *)applicationTemporaryDirectory;
- (NSDistantObject <MojoProtocol> *)mojoProxy;

- (int)serverPortNumber;

- (BOOL)addServerPortMapping;
- (void)removeServerPortMapping;
- (TCMPortMapping *)serverPortMapping;

- (void)updateITunesInfo;
- (void)forceUpdateITunesInfo;

@end
