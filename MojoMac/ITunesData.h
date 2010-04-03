#import <Foundation/Foundation.h>

#define LIBRARY_PERSISTENTID         @"Library Persistent ID"
#define MUSIC_FOLDER                 @"Music Folder"

#define TRACK_ID                     @"Track ID"
#define TRACK_PERSISTENTID           @"Persistent ID"
#define TRACK_LOCATION               @"Location"
#define TRACK_KIND                   @"Kind"
#define TRACK_TYPE                   @"Track Type"
#define TRACK_FILESIZE               @"Size"
#define TRACK_TOTALTIME              @"Total Time"
#define TRACK_DATEADDED              @"Date Added"
#define TRACK_BITRATE                @"Bit Rate"
#define TRACK_PLAYCOUNT              @"Play Count"
#define TRACK_NAME                   @"Name"
#define TRACK_ARTIST                 @"Artist"
#define TRACK_ALBUM                  @"Album"
#define TRACK_GENRE                  @"Genre"
#define TRACK_COMPOSER               @"Composer"
#define TRACK_RATING                 @"Rating"
#define TRACK_TRACKNUMBER            @"Track Number"
#define TRACK_TRACKCOUNT             @"Track Count"
#define TRACK_DISCNUMBER             @"Disc Number"
#define TRACK_DISCCOUNT              @"Disc Count"
#define TRACK_YEAR                   @"Year"
#define TRACK_BPM                    @"BPM"
#define TRACK_COMMENTS               @"Comments"
#define TRACK_ISPROTECTED            @"Protected"
#define TRACK_HASVIDEO               @"Has Video"

#define PLAYLIST_ID                  @"Playlist ID"
#define PLAYLIST_PERSISTENTID        @"Playlist Persistent ID"
#define PLAYLIST_PARENT_PERSISTENTID @"Parent Persistent ID"
#define PLAYLIST_NAME                @"Name"
#define PLAYLIST_ITEMS               @"Playlist Items"
#define PLAYLIST_TYPE                @"DD:Playlist Type"
#define PLAYLIST_CHILDREN            @"DD:Children"

#define PLAYLIST_TYPE_MASTER         0
#define PLAYLIST_TYPE_MUSIC          1
#define PLAYLIST_TYPE_MOVIES         2
#define PLAYLIST_TYPE_TVSHOWS        3
#define PLAYLIST_TYPE_PODCASTS       4
#define PLAYLIST_TYPE_VIDEOS         5
#define PLAYLIST_TYPE_AUDIOBOOKS     6
#define PLAYLIST_TYPE_PURCHASED      7
#define PLAYLIST_TYPE_PARTYSHUFFLE   8
#define PLAYLIST_TYPE_FOLDER         9
#define PLAYLIST_TYPE_SMART          10
#define PLAYLIST_TYPE_NORMAL         11

/**
 * The ITunesData class provides low-level access to all information in the iTunes XML file.
 * This is the base class for all other iTunes data and info.
 * Both playlists and tracks are stored in dictionaries.
 * Keys to both playlist and track dictionaries are defined above.
**/
@interface ITunesData : NSObject
{
	// Dictionary with contents of music library xml file
	NSMutableDictionary *library;
	
	// Maps from playlist persistent ID to the playlist dictionary
	NSMutableDictionary *playlistMappings;
	
	// Contains top level playlists
	NSMutableArray *playlistHeirarchy;
	
	// You can get a playlist's children with the PLAYLIST_CHILDREN key.
	// This returns an array of playlist persistent ids.
	// Use the playlistForPersistentID method to get the child playlist dictionary.
}

+ (ITunesData *)allLocalITunesData;
+ (void)flushAllLocalITunesData;

+ (NSString *)localITunesMusicLibraryXMLPath;

- (id)initWithXMLPath:(NSString *)xmlPath;
- (id)initWithXMLData:(NSData *)xmlData;

- (NSString *)libraryPersistentID;
- (NSString *)musicFolder;

- (NSMutableDictionary *)tracks;

- (NSMutableArray *)playlists;
- (NSMutableArray *)playlistHeirarchy;

- (NSMutableDictionary *)playlistForIndex:(int)playlistIndex;
- (NSMutableDictionary *)playlistForPersistentID:(NSString *)persistentID;

- (NSMutableDictionary *)masterPlaylist;

- (NSMutableDictionary *)trackForID:(int)trackID;

- (int)numberOfTracks;

- (int)validateTrackID:(int)trackID withPersistentTrackID:(NSString *)persistentTrackID;
- (int)validatePlaylistIndex:(int)playlistIndex withPersistentPlaylistID:(NSString *)persistentPlaylistID;

@end