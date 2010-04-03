#import <Foundation/Foundation.h>


@interface AppDelegate : NSObject
{
	long lastCanSystemSleepNotificationID;
	long lastSystemWillSleepNotificationID;
}

- (void)replyToCanSystemSleepWithResult:(BOOL)flag;
- (void)replyToSystemWillSleep;

- (NSString *)applicationSupportDirectory;

- (BOOL)isMojo;
- (BOOL)isMojoHelper;

- (NSString *)mojoPath;
- (NSString *)mojoHelperPath;

@end
