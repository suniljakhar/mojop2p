#import <Foundation/Foundation.h>

@class BonjourResource;

// This class will post the following notifications (defined in MojoDefinitions.h):
// 
// DidFindLocalServiceNotification
// DidUpdateLocalServiceNotification
// DidRemoveLocalServiceNotification


@interface BonjourClient : NSObject
{
	NSNetServiceBrowser *serviceBrowser;
	
	NSMutableDictionary *availableResources;
	
	NSString *localhostServiceName;
}

+ (BonjourClient *)sharedInstance;

- (void)start;
- (void)stop;

- (NSString *)localhostServiceName;
- (void)setLocalhostServiceName:(NSString *)newLocalhostServiceName;

- (BOOL)isLibraryAvailable:(NSString *)libID;

- (BonjourResource *)resourceForLibraryID:(NSString *)libID;

- (void)setNickname:(NSString *)nickname forLibraryID:(NSString *)libID;

- (NSMutableArray *)unsortedResourcesIncludingLocalhost:(BOOL)flag;
- (NSMutableArray *)sortedResourcesByNameIncludingLocalhost:(BOOL)flag;

@end
