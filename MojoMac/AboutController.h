/* AboutController */

#import <Cocoa/Cocoa.h>

@interface AboutController : NSObject
{
	BOOL isDisplayingRegistartion;
	BOOL hasStuntUUID;
	
    IBOutlet id panel;
    IBOutlet id registrationField;
    IBOutlet id textView;
    IBOutlet id versionField;
}

- (IBAction)toggleRegistrationField:(id)sender;

@end
