#import "ITunesForeignData.h"

@class ITunesTrack;
@class ITunesPlaylist;
@class LibrarySubscriptions;

#define TRACK_DOWNLOADSTATUS   @"DD:Download Status"
#define TRACK_ISPLAYING        @"DD:Is Playing"

#define PLAYLIST_ISSUBSCRIBED  @"DD:Is Subscribed"
#define PLAYLIST_MYNAME        @"DD:My Name"


/**
 * The ITunesForeignInfo class is designed to be used with cocoa bindings.
 * Instead of accessing raw iTunes data with dictionaries, wrapper classes can be used.
 * These proxies may be used as content for binding controller classes.
 * In addition, it provides support for subscription modifications.
**/
@interface ITunesForeignInfo : ITunesForeignData
{
	NSDictionary *iTunesTracks;
	NSArray *iTunesPlaylists;
	
	LibrarySubscriptions *librarySubscriptions;
}

- (id)initWithXMLPath:(NSString *)xmlPath;
- (id)initWithXMLData:(NSData *)xmlData;

- (NSArray *)iTunesPlaylists;
- (ITunesPlaylist *)iTunesMasterPlaylist;

- (ITunesTrack *)iTunesTrackForID:(int)trackID;

- (void)setLibrarySubscriptions:(LibrarySubscriptions *)ls;

- (void)commitSubscriptionChanges;
- (void)discardSubscriptionChanges;

@end

// DELEGATE
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (ITunesForeignInfoDelegate)

- (void)iTunesForeignInfo:(ITunesForeignInfo *)data didFindConnectionForITunesTrack:(ITunesTrack *)track;

@end