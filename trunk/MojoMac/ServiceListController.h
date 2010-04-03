#import <Cocoa/Cocoa.h>

@interface ServiceListController : NSObject
{
	NSNumberFormatter *numberFormatter;
	
	NSMutableDictionary *largeText;
	NSMutableDictionary *smallText;
	NSMutableDictionary *whiteLargeText;
	NSMutableDictionary *whiteSmallText;
	NSMutableDictionary *grayLargeText;
	NSMutableDictionary *graySmallText;
	
	NSArray *sortedOnlineServices;
	NSArray *sortedOfflineServices;
	
	BOOL isDisplayingShareName;
	BOOL hasUpdatedServerList;
	
	// Interface Builder Outlets
	IBOutlet id accountErrorSheet;
    IBOutlet id addBuddyErrorField;
    IBOutlet id addBuddyHostnameField;
    IBOutlet id addBuddyNicknameField;
    IBOutlet id addBuddySheet;
    IBOutlet id addBuddyUsernameField;
    IBOutlet id authErrorSheet;
    IBOutlet id getInfoBonjourField;
    IBOutlet id getInfoJabberField;
    IBOutlet id getInfoNameField;
	IBOutlet id getInfoOkButton;
    IBOutlet id getInfoSheet;
    IBOutlet id internetSheet;
    IBOutlet id internetURLField;
    IBOutlet id invalidURLField;
    IBOutlet id myIPField;
    IBOutlet id plusButton;
    IBOutlet id serviceButton;
    IBOutlet id serviceListWindow;
    IBOutlet id serviceTable;
    IBOutlet id shareNameOrJIDField;
    IBOutlet id statusPulldown;
}

- (IBAction)accountError_ok:(id)sender;
- (IBAction)addBuddy:(id)sender;
- (IBAction)addBuddy_cancel:(id)sender;
- (IBAction)addBuddy_ok:(id)sender;
- (IBAction)authError_ok:(id)sender;
- (IBAction)changeStatus:(id)sender;
- (IBAction)didClickOpenURL:(id)sender;
- (IBAction)didClickServiceButton:(id)sender;
- (IBAction)getInfo_cancel:(id)sender;
- (IBAction)getInfo_ok:(id)sender;
- (IBAction)internet_cancel:(id)sender;
- (IBAction)internet_learnMore:(id)sender;
- (IBAction)internet_ok:(id)sender;
- (IBAction)shareNameOrJIDClicked:(id)sender;

@end
