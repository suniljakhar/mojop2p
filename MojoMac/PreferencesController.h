#import <Cocoa/Cocoa.h>
@class  ITunesLocalSharedData;

#define ShareNameDidChangeNotification  @"ShareNameDidChange"
#define JIDDidChangeNotification        @"JIDDidChange"


@interface PreferencesController : NSObject
{
	NSToolbar *toolbar;
	NSMutableDictionary *items;
	
	BOOL isXMPPClientDisconnected;
	
	BOOL shouldRefreshITunesInfo;
	BOOL isPlaylistsPopupReady;
	BOOL isPlaylistsTableReady;
	
	ITunesLocalSharedData *data;
	NSTimer *updateSharingInfoTimer;
	
	// Interface Builder Outlets
    IBOutlet id accountsView;
    IBOutlet id addFromSubscriptionsButton;
    IBOutlet id advancedView;
    IBOutlet id amazonLinksCheckbox;
    IBOutlet id autoLoginButton;
    IBOutlet id createNewAccountButton;
    IBOutlet id enableHelperAppButton;
    IBOutlet id generalView;
    IBOutlet id iTunesView;
    IBOutlet id launchAtLoginButton;
    IBOutlet id passwordField;
    IBOutlet id playlistMatrix;
    IBOutlet id playlistsField;
    IBOutlet id playlistsPopup;
    IBOutlet id preferencesWindow;
    IBOutlet id requirePasswordButton;
    IBOutlet id requireTLSButton;
    IBOutlet id serverPortField;
    IBOutlet id shareNameField;
	IBOutlet id sharingMatrix;
	IBOutlet id sharingTable;
	IBOutlet id sharingView;
    IBOutlet id showMenuItemButton;
    IBOutlet id softwareUpdateView;
	IBOutlet id stuntFeedbackButton;
    IBOutlet id updateIntervalPopup;
    IBOutlet id xmppAllowSSCButton;
    IBOutlet id xmppAllowMismatchButton;
    IBOutlet id xmppPasswordField;
    IBOutlet id xmppPortField;
    IBOutlet id xmppResourceField;
    IBOutlet id xmppServerField;
    IBOutlet id xmppUsernameField;
    IBOutlet id xmppUseSSLButton;
    IBOutlet id iTunesLocationButton;
    IBOutlet id iTunesLocationField;
}

- (IBAction)changePlaylistName:(id)sender;
- (IBAction)changePlaylistSelection:(id)sender;
- (IBAction)changeServerPort:(id)sender;
- (IBAction)changeXMPPPassword:(id)sender;
- (IBAction)changeXMPPPort:(id)sender;
- (IBAction)changeXMPPResource:(id)sender;
- (IBAction)changeXMPPServer:(id)sender;
- (IBAction)changeXMPPUsername:(id)sender;
- (IBAction)createNewAccount:(id)sender;
- (IBAction)goToAnswers:(id)sender;
- (IBAction)passwordDidChange:(id)sender;
- (IBAction)playlistMatrixDidChange:(id)sender;
- (IBAction)revertToDefaultXMPPSettings:(id)sender;
- (IBAction)shareNameDidChange:(id)sender;
- (IBAction)sharingMatrixDidChange:(id)sender;
- (IBAction)toggleAddFromSubscriptions:(id)sender;
- (IBAction)toggleDemoMode:(id)sender;
- (IBAction)toggleEnableHelperApp:(id)sender;
- (IBAction)toggleLaunchAtLogin:(id)sender;
- (IBAction)toggleRequirePassword:(id)sender;
- (IBAction)toggleRequireTLS:(id)sender;
- (IBAction)toggleShowMenuItem:(id)sender;
- (IBAction)toggleXMPPAllowSelfSignedCertificates:(id)sender;
- (IBAction)toggleXMPPAllowSSLHostNameMismatch:(id)sender;
- (IBAction)toggleXMPPAutoLogin:(id)sender;
- (IBAction)toggleXMPPUseSSL:(id)sender;
- (IBAction)updateIntervalDidChange:(id)sender;
- (IBAction)changeITunesLocation:(id)sender;
- (IBAction)selectITunesLocation:(id)sender;
- (IBAction)toggleStuntFeedback:(id)sender;
- (IBAction)learnMoreAboutStuntFeedback:(id)sender;

- (void)showAccountsSection;

@end
