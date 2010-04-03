#import <Cocoa/Cocoa.h>

@class BonjourResource;
@class XMPPUserAndMojoResource;
@class SocketConnector;
@class LibrarySubscriptions;
@class ITunesForeignInfo;
@class HTTPClient;

#define SubscriptionsDidChangeNotification  @"SubscriptionsDidChange"


@interface SubscriptionsController : NSWindowController
{
	// Stored reference to service list window (not retained)
	NSWindow *dockingWindow;
	
	// The library which we are editing subscriptions for
	NSString *libraryID;
	
	// The set of subscriptions which we are editing
	LibrarySubscriptions *librarySubscriptions;
	
	// Stored BonjourUser (if browsing local service)
	BonjourResource *bonjourResource;
		
	// Stored XMPP user and resource (if browsing remote service)
	XMPPUserAndMojoResource *xmppUserResource;
	
	// Variables used for downloading files from a mojo server
	SocketConnector *socketConnector;
	UInt16 gatewayPort;
	NSURL *baseURL;
	HTTPClient *httpClient;
	
	// The parsed iTunes data (if available)
	ITunesForeignInfo *data;
	
	// Current status - so we know what to stop if we need to stop
	int status;
	
	// Whether to display the short version of the total playlist time, or the long version
	BOOL totalAvailableUsingLongView;
	
    IBOutlet id lastUpdateField;
    IBOutlet id okButton;
    IBOutlet id passwordField;
    IBOutlet id playlistsController;
    IBOutlet id progress;
    IBOutlet id progressText;
    IBOutlet id subscriptionsPanel;
    IBOutlet id subscriptionsTable;
    IBOutlet id totalAvailable;
    IBOutlet id unsubscribePanel;
    IBOutlet id updateNowButton;
}
- (id)initWithDockingWindow:(NSWindow *)dockingWindow;

- (void)editSubscriptionsForLocalResource:(BonjourResource *)bonjourResource;
- (void)editSubscriptionsForRemoteResource:(XMPPUserAndMojoResource *)xmppUserResource;
- (void)editSubscriptionsForLibraryID:(NSString *)libID;

- (IBAction)cancel_subscriptions:(id)sender;
- (IBAction)cancel_unsubscribe:(id)sender;
- (IBAction)ok_susbscriptions:(id)sender;
- (IBAction)ok_unsubscribe:(id)sender;
- (IBAction)passwordEntered:(id)sender;
- (IBAction)totalAvailableClicked:(id)sender;
- (IBAction)updateNow_subscriptions:(id)sender;

@end
