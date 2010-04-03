#import <Foundation/Foundation.h>

@class ITunesData;


@interface LibrarySubscriptions : NSObject <NSCopying, NSCoding>
{
	NSString *libraryID;
	
	NSMutableDictionary *subscriptions;
	NSString *displayName;
	NSDate *lastSyncDate;
	BOOL isUpdating;
}

- (id)initWithLibraryID:(NSString *)libID;
- (id)initWithLibraryID:(NSString *)libID dictionary:(NSDictionary *)dictionary;

- (BOOL)isEssentiallyEqual:(LibrarySubscriptions *)ls;

- (NSDictionary *)prefsDictionary;

- (int)numberOfSubscribedPlaylists;

- (NSArray *)subscribedPlaylistsWithData:(ITunesData *)data;

- (void)unsubscribeFromPlaylist:(NSDictionary *)playlist;
- (void)unsubscribeFromAllPlaylists;
- (void)subscribeToPlaylist:(NSDictionary *)playlist withPlaylistIndex:(int)index myName:(NSString *)myName;

- (BOOL)isSubscribedToPlaylist:(NSDictionary *)playlist;

- (NSString *)myNameForPlaylist:(NSDictionary *)playlist;

- (NSString *)libraryID;

- (NSString *)displayName;
- (void)setDisplayName:(NSString *)name;

- (NSDate *)lastSyncDate;
- (void)setLastSyncDate:(NSDate *)date;

- (BOOL)isUpdating;
- (void)setIsUpdating:(BOOL)flag;

@end
