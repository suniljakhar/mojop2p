#import "AboutController.h"
#import "MojoAppDelegate.h"


@implementation AboutController

/**
 * Called automatically via Cocoa after the nib is loaded and ready
**/
- (void)awakeFromNib
{
	// Center the About panel
	[panel center];
	
	// Setup the version field
	NSString *versionNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *buildNumber   = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	
	NSString *versionStr = NSLocalizedString(@"Version %@ (%@)", @"Version Display in About Panel");
	[versionField setStringValue:[NSString stringWithFormat:versionStr, versionNumber, buildNumber]];
	
	// Setup registration field
	[registrationField setStringValue:@"    "];
	
	isDisplayingRegistartion = YES;
	hasStuntUUID = NO;
	
	// We can't get the actual stunt uuid until we have a DO connection to MojoHelper
	// So we register for the notification that tells us when the helperProxy is ready
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(helperProxyReady:)
												 name:HelperProxyReadyNotification
											   object:nil];
	
	// Setup the credits...
	NSString *aboutPath = [[NSBundle mainBundle] pathForResource:@"about" ofType:@"rtf"];
	
	[textView readRTFDFromFile:aboutPath];
}

/**
 * This method is called (via notifications) when the helper proxy is setup and ready.
 * This allows us to setup our preferences items that correlate to preferences in the helper app.
 **/
- (void)helperProxyReady:(NSNotification *)notification
{
	NSString *stuntUUID = [[[NSApp delegate] helperProxy] stuntUUID];
	
	[[registrationField cell] setPlaceholderString:stuntUUID];
	
	hasStuntUUID = YES;
}

- (IBAction)toggleRegistrationField:(id)sender
{
	if(hasStuntUUID)
	{
		NSString *text = [registrationField stringValue];
		NSString *placeholderText = [[registrationField cell] placeholderString];
		
		[registrationField setStringValue:placeholderText];
		[[registrationField cell] setPlaceholderString:text];
		
		isDisplayingRegistartion = !isDisplayingRegistartion;
	}
}

@end
