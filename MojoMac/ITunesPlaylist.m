#import "ITunesPlaylist.h"
#import "ITunesTrack.h"

#import "ITunesData.h"
#import "ITunesForeignData.h"
#import "ITunesForeignInfo.h"


@implementation ITunesPlaylist

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates a playlist structure from the given iTunesData instance.
 * The 'structure' is simply an nsArray of PlaylistData objects.
 * Each object in the array is a top-level playlist, with sub-playlists available via the PlaylistData's children.
**/
+ (NSArray *)createPlaylistsForData:(ITunesForeignInfo *)data
{
	NSArray *playlistHeirarchy = [data playlistHeirarchy];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[playlistHeirarchy count]];
	
	unsigned int i;
	for(i = 0; i < [playlistHeirarchy count]; i++)
	{
		NSMutableDictionary *playlist = [playlistHeirarchy objectAtIndex:i];
		
		ITunesPlaylist *temp = [[ITunesPlaylist alloc] initWithPlaylist:playlist parent:nil forData:data];
		
		[result addObject:temp];
		[temp release];
	}
	
	// Return immutable autoreleased copy
	
	return [[result copy] autorelease];
}

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sole Constructor.
 * This method creates a playlist wrapper using the given playlist and parent.
 * It also recursively creates all its children, grandchildren, etc.
**/
- (id)initWithPlaylist:(NSMutableDictionary *)playlist
				parent:(ITunesPlaylist *)parent
			   forData:(ITunesForeignInfo *)data
{
	if((self = [super init]))
	{
		unsigned int i;
		
		// Store a reference to the actual playlist.
		// Remember that this object is a child of data, and data takes care of retaining the playlist.
		// Children do NOT retain their parents, only parents retain their children.
		playlistRef = playlist;
		
		// Store a reference to the parent.
		// Children do NOT retain their parents, only parents retain their children.
		parentRef = parent;
		
		// 
		// Notice that variables that end with 'Ref' don't retain their values
		// 
		
		// Create list of tracks
		
		NSArray *playlistItems = [playlistRef objectForKey:PLAYLIST_ITEMS];
		
		NSMutableArray *tempTracks = [NSMutableArray arrayWithCapacity:[playlistItems count]];
		
		for(i = 0; i < [playlistItems count]; i++)
		{
			// The playlistItem is actually a dictionary with a single key/value pair
			
			NSDictionary *playlistItem = [playlistItems objectAtIndex:i];
			int trackID = [[playlistItem objectForKey:TRACK_ID] intValue];
			
			// For some reason, Podcasts often have invalid Track ID's... so we have to be careful here.
			
			ITunesTrack *track = [data iTunesTrackForID:trackID];
			if(track)
			{
				[tempTracks addObject:track];
			}
		}
		
		// Create list of children
		
		NSArray *playlistChildren = [playlistRef objectForKey:PLAYLIST_CHILDREN];
		
		NSMutableArray *tempChildren = [NSMutableArray arrayWithCapacity:[playlistChildren count]];
		
		for(i = 0; i < [playlistChildren count]; i++)
		{
			NSString *childPlaylistPersistentID = [playlistChildren objectAtIndex:i];
			
			NSMutableDictionary *childPlaylist = [data playlistForPersistentID:childPlaylistPersistentID];
			
			ITunesPlaylist *child = [[[ITunesPlaylist alloc] initWithPlaylist:childPlaylist
																	   parent:self
																	  forData:data] autorelease];
			[tempChildren addObject:child];
		}
		
		// Store immutable versions of tracks and children
		
		tracks = [tempTracks copy];
		children = [tempChildren copy];
	}
	return self;
}

/**
 * Standard Deconstructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
//	NSLog(@"Destroying self: %@", self);
	[children release];
	[tracks release];
	[searchString release];
	[super dealloc];
}

// ACCESSOR METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the persistent ID of the playlist.
**/
- (NSString *)persistentID {
	return [playlistRef objectForKey:PLAYLIST_PERSISTENTID];
}

/**
 * Returns the name of the playlist.
**/
- (NSString *)name {
	return [playlistRef objectForKey:PLAYLIST_NAME];
}

/**
 * Returns whether or not the user is subscribed to the playlist.
 * Note that this is the current subscription state, which may or may not be committed yet.
**/
- (BOOL)isSubscribed {
	return [[playlistRef objectForKey:PLAYLIST_ISSUBSCRIBED] boolValue];
}

/**
 * Subscribes (or unsubscribes) the user from the playlist.
 * Note that changes must be committed (see ITunesForeignInfo) before they take effect.
**/
- (void)setIsSubscribed:(BOOL)flag {
	[playlistRef setObject:[NSNumber numberWithBool:flag] forKey:PLAYLIST_ISSUBSCRIBED];
}

/**
 * Returns the name the playlist will have if it is subscribed to, and synced to the user's machine.
 * Note that this is the current myName variable, which may or may not be committed yet.
**/
- (NSString *)myName {
	return [playlistRef objectForKey:PLAYLIST_MYNAME];
}

/**
 * Sets the name the playlist will have if it is subscribed to, and synced to the user's machine.
 * Note that changes must be committed (see ITunesForeignInfo) before they take effect.
**/
- (void)setMyName:(NSString *)myName
{
	[playlistRef setObject:myName forKey:PLAYLIST_MYNAME];
}

/**
 * Returns an array of children.
 * Each object in the array is of type ITunesPlaylist.
**/
- (NSArray *)children {
	return children;
}

/**
 * Returns an array of tracks.
 * Each object in the array is of type ITunesTrack.
**/
- (NSArray *)tracks {
	return tracks;
}

/**
 * Returns the parent Playlist of this Playlist.
 * If this playlist is a top level playlist, this method returns nil.
**/
- (ITunesPlaylist *)parent {
	return parentRef;
}

/**
 * Returns the playlist type.
 * This will be one of the defined types in ITunesData, such as PLAYLIST_TYPE_SMART, PLAYLIST_TYPE_AUDIOBOOKS, etc.
**/
- (int)type {
	return [[playlistRef objectForKey:PLAYLIST_TYPE] intValue];
}

/**
 * Returns the saved search string associated with this playlist.
 * If there is no saved search string, this method simply returns an empty string.
**/
- (NSString *)searchString
{
	if(searchString)
		return searchString;
	else
		return @"";
}

- (void)setSearchString:(NSString *)newSearchString
{
	if(![searchString isEqualToString:newSearchString])
	{
		[searchString release];
		searchString = [newSearchString copy];
	}
}

@end
