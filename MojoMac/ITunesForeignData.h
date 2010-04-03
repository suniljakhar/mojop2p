#import "ITunesData.h"

#define TRACK_CONNECTION  @"DD:Connection"

/**
 * The ITunesForeignData class extends the ITunesData class to add analysis of non-local data.
 * The tracks can be compared against the tracks in the local iTunes library, with matches stored as connections.
**/
@interface ITunesForeignData : ITunesData
{
	id delegate;
}

- (id)initWithXMLPath:(NSString *)xmlPath;
- (id)initWithXMLData:(NSData *)xmlData;

- (id)delegate;
- (void)setDelegate:(id)newDelegate;

- (void)calculateConnections;
- (void)calculateConnectionsInBackground;

- (void)addConnectionBetweenTrack:(NSMutableDictionary *)track andLocalTrack:(NSDictionary *)localTrack;

@end

// DELEGATE
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (ITunesForeignDataDelegate)

- (void)iTunesForeignData:(ITunesForeignData *)data didFindConnectionForTrack:(NSDictionary *)track;

@end