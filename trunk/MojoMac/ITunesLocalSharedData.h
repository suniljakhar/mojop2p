#import "ITunesData.h"

#define PLAYLIST_STATE     @"DD:State"

/**
 * The ITunesLocalSharedData class provides low-level access to shared iTunes information.
 * Both playlists and tracks are stored in dictionaries.
 * Keys to both playlist and track dictionaries are defined above, and in iTunesData.h
**/
@interface ITunesLocalSharedData : ITunesData

+ (ITunesLocalSharedData *)sharedLocalITunesData;
+ (void)flushSharedLocalITunesData;

- (id)initWithXMLPath:(NSString *)xmlPath;
- (id)initWithXMLData:(NSData *)xmlData;

- (void)setState:(int)state ofPlaylist:(NSMutableDictionary *)playlist;
- (void)toggleStateOfPlaylist:(NSMutableDictionary *)playlist;

- (NSData *)serializedData;

- (void)saveChanges;

- (void)printPlaylists;
- (void)printPlaylistHeirarchy;

@end
