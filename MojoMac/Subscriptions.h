#import <Foundation/Foundation.h>
@class  LibrarySubscriptions;

#define SubscriptionsDidChangeNotification  @"SubscriptionsDidChange"


@interface Subscriptions : NSObject

/**
 * Returns an array of all the subscriptions.
 * That is, each object in the array will be of type LibrarySubscriptions.
 * The objects in the array are the actual LibrarySubscripitons being used by this class, and as such,
 * should not be modified in any manner.
**/
+ (NSMutableArray *)sortedSubscriptionsByName;

/**
 * Returns a clone (autoreleased copy) of the LibrarySubscriptions for the given library ID.
 * This clone is a deep copy of the original, and may be modified as needed.
 * To actually commit any changes to the subscriptions, use the various setSubscriptions:forLibrary: methods.
**/
+ (LibrarySubscriptions *)subscriptionsCloneForLibrary:(NSString *)libID;

/**
 * Description forthcoming...
**/
+ (void)setSubscriptions:(LibrarySubscriptions *)subscriptions forLibrary:(NSString *)libID;

/**
 * Call this method to reschedule the time at which we should next update our subscriptions.
 * This method is generally called from a timer, but if no timer is used, simply pass nil.
**/
+ (void)updateTimer:(NSTimer *)aTimer;

@end
