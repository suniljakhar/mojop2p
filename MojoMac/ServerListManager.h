#import <Foundation/Foundation.h>

#define DidUpdateServerListNotification    @"DidUpdateServerList"
#define DidNotUpdateServerListNotification @"DidNotUpdateServerList"


@interface ServerListManager : NSObject

+ (NSString *)serverListPath;

+ (BOOL)serverListNeedsUpdate;
+ (void)updateServerList;

@end
