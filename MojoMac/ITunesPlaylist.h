#import <Foundation/Foundation.h>

@class ITunesData;
@class ITunesForeignData;
@class ITunesForeignInfo;


@interface ITunesPlaylist : NSObject
{
	NSMutableDictionary *playlistRef;
	
	ITunesPlaylist *parentRef;
	NSArray *children;
	NSArray *tracks;
	
	NSString *searchString;
}

+ (NSArray *)createPlaylistsForData:(ITunesForeignInfo *)data;

- (id)initWithPlaylist:(NSMutableDictionary *)playlist
				parent:(ITunesPlaylist *)parent
			   forData:(ITunesForeignInfo *)data;

- (NSString *)persistentID;
- (NSString *)name;

- (BOOL)isSubscribed;
- (void)setIsSubscribed:(BOOL)flag;

- (NSString *)myName;
- (void)setMyName:(NSString *)myName;

- (NSArray *)children;
- (NSArray *)tracks;

- (ITunesPlaylist *)parent;

- (int)type;

- (NSString *)searchString;
- (void)setSearchString:(NSString *)newSearchString;

@end
