#import <Cocoa/Cocoa.h>
@class   XMPPStream;

#define DidCreateXMPPAccountNotification  @"DidCreateXMPPAccount"


@interface WelcomeController : NSWindowController
{
	BOOL isConnecting;
	BOOL manualDisconnect;
	XMPPStream *xmppStream;
	
	NSString *regServer;
	NSString *regUsername;
	NSString *regPassword;
	
	// Interface Builder Outlets
	IBOutlet id contentBox;
	IBOutlet id view1;
	IBOutlet id view2;
	IBOutlet id view3;
	
	IBOutlet id nextButton;
	
	IBOutlet id limitErrorMessage;
	IBOutlet id serverField;
	IBOutlet id serverErrorMessage;
	IBOutlet id serverProgressIndicator;
	IBOutlet id usernameField;
	IBOutlet id usernameErrorMessage;
	IBOutlet id clearPasswordField;
	IBOutlet id shadowPasswordField;
	IBOutlet id passwordErrorMessage;
	IBOutlet id progressIndicator;
	IBOutlet id connectErrorMessage;
    IBOutlet id registerButton;
	
	IBOutlet id cancelSheet;
	
	IBOutlet id mojoIdField;
	IBOutlet id doneButton;
}

- (IBAction)next:(id)sender;

- (IBAction)toggleShowPassword:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)createAccount:(id)sender;
- (IBAction)goToAnswers:(id)sender;
- (IBAction)useExistingAccount:(id)sender;

- (IBAction)cancel_no:(id)sender;
- (IBAction)cancel_yes:(id)sender;

- (IBAction)goToForum:(id)sender;
- (IBAction)done:(id)sender;

@end
