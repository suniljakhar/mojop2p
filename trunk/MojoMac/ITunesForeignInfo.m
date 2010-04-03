#import "ITunesForeignInfo.h"
#import "ITunesPlaylist.h"
#import "ITunesTrack.h"
#import "LibrarySubscriptions.h"
#import "MojoAppDelegate.h"
#import "HelperProtocol.h"

@interface ITunesForeignInfo (PrivateAPI)
- (void)setPlaylistInfoFromLibrarySubscriptions;
@end


@implementation ITunesForeignInfo

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes iTunesData, iTunesForeignData, and iTunesForeignInfo.
 * The iTunesData is initialized using the given path to an iTunes Music Library xml file.
 * 
 * Note: Since this method initializes the iTunesData, it may take several seconds to complete.
**/
- (id)initWithXMLPath:(NSString *)xmlPath
{
	if((self = [super initWithXMLPath:xmlPath]))
	{
		// Create the iTunesTracks
		// This must be done before we create the iTunesPlaylists
		iTunesTracks = [[ITunesTrack createTracksForData:self] retain];
		
		// Create the playlist structure
		iTunesPlaylists = [[ITunesPlaylist createPlaylistsForData:self] retain];
	}
	return self;
}

/**
 * Initializes iTunesData, iTunesForeignData, and iTunesForeignInfo.
 * The iTunesData is initialized using the given data containing an iTunes Music Library xml file.
 *
 * Note: Since this method initializes the iTunesData, it may take several seconds to complete.
**/
- (id)initWithXMLData:(NSData *)xmlData
{
	if((self = [super initWithXMLData:xmlData]))
	{
		// Create the iTunesTracks
		// This must be done before we create the iTunesPlaylists
		iTunesTracks = [[ITunesTrack createTracksForData:self] retain];
		
		// Create the playlist structure
		iTunesPlaylists = [[ITunesPlaylist createPlaylistsForData:self] retain];
	}
	return self;
}

/**
 * Releases all memory associated with this class instance.
**/
- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	[iTunesTracks release];
	[iTunesPlaylists release];
	[librarySubscriptions release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ITunesPlaylist and ITunesTrack Access
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns an array of ITunesPlaylist objects.
 * This is the playlist structure for the ITunesData.
 * Each object in the array is a top-level playlist, and children may be accessed via the ITunesPlaylist objects.
 * The ITunesPlaylist objects are KVC comliant, and are suitable for use in Cocoa Bindings.
**/
- (NSArray *)iTunesPlaylists
{
	return iTunesPlaylists;
}

- (ITunesPlaylist *)iTunesMasterPlaylist
{
	if([iTunesPlaylists count] > 0)
		return [iTunesPlaylists objectAtIndex:0];
	else
		return nil;
}

- (ITunesTrack *)iTunesTrackForID:(int)trackID;
{
	return [iTunesTracks objectForKey:[NSString stringWithFormat:@"%i", trackID]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Playlist Subscriptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sets the playlist subscriptions for the given data, allowing automatic
 * playlist configuration (PLAYLIST_ISSUBSCRIBED, PLAYLIST_MYNAME) from the LibrarySubscriptions object.
 * This method should be called after initialization, and to discard subscription changes.
**/
- (void)setLibrarySubscriptions:(LibrarySubscriptions *)ls
{
	// Save reference to given playlist subscriptions (if different from what we currently have)
	if(librarySubscriptions != ls)
	{
		[librarySubscriptions release];
		librarySubscriptions = [ls retain];
	}
	
	NSArray *playlists = [self playlists];
	
	int i;
	for(i = 0; i < [playlists count]; i++)
	{
		NSMutableDictionary *currentPlaylist = [playlists objectAtIndex:i];
		
		BOOL isSubscribed = [librarySubscriptions isSubscribedToPlaylist:currentPlaylist];
		[currentPlaylist setObject:[NSNumber numberWithBool:isSubscribed] forKey:PLAYLIST_ISSUBSCRIBED];
		
		NSString *myName = [librarySubscriptions myNameForPlaylist:currentPlaylist];
		[currentPlaylist setObject:myName forKey:PLAYLIST_MYNAME];
	}
}

/**
 * Commits any changes to the playlist subscriptions.
 * This is done by sending the information to our MojoHelper background application.
 * 
 * Note: This method has no effect if the LibrarySubscriptions haven't been setup. (See setLibrarySubscriptions: method)
 * Note: This method must be invoked on the primary thread!
**/
- (void)commitSubscriptionChanges
{
	// Verify we have a set of playlist subscriptions
	if(librarySubscriptions == nil)
	{
		// The LibrarySubscriptions have not been configured - Ignore request.
		return;
	}
	
	// First unsubscribe from all playlists so we start with an empty slate
	[librarySubscriptions unsubscribeFromAllPlaylists];
	
	// Now we need to loop through all playlists, and subscribe to those that are set to be subscribed to
	NSArray *playlists = [self playlists];
	
	int i;
	for(i = 0; i < [playlists count]; i++)
	{
		NSMutableDictionary *currentPlaylist = [playlists objectAtIndex:i];
		
		if([[currentPlaylist objectForKey:PLAYLIST_ISSUBSCRIBED] boolValue])
		{
			[librarySubscriptions subscribeToPlaylist:currentPlaylist
									withPlaylistIndex:i
											   myName:[currentPlaylist objectForKey:PLAYLIST_MYNAME]];
		}
	}
	
	// Send our updated librarySubscriptions object to our MojoHelper background application
	id helperProxy = [[NSApp delegate] helperProxy];
	[helperProxy setSubscriptions:librarySubscriptions forLibrary:[self libraryPersistentID]];
}

/**
 * Discards any playlist subscription changes that have not been committed.
 * This will have the result of resetting the playlist subscription information to how it was after the last commit.
 *
 * Note: This method has no effect if the LibrarySubscriptions haven't been setup. (See setLibrarySubscriptions: method)
**/
- (void)discardSubscriptionChanges
{
	// Verify we have a set of playlist subscriptions
	if(librarySubscriptions == nil)
	{
		// The LibrarySubscriptions have not been configured - Ignore request.
		return;
	}
	
	// We need to reset all isSubscribed and myName info to reflect the current librarySubscriptions.
	[self setLibrarySubscriptions:librarySubscriptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Overriden Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * We override this method so that we can support our own delegate method.
 * Our delegate method is pretty much the same as the one in ITunesForeignData,
 * except it passes the higher level ITunesTrack wrapper instead of the low-level track dictionary
**/
- (void)addConnectionBetweenTrack:(NSMutableDictionary *)track andLocalTrack:(NSDictionary *)localTrack
{
	// Add connection to track
	[track setObject:[localTrack objectForKey:TRACK_ID] forKey:TRACK_CONNECTION];
	
	// Invoke delegate method if a delegate is set, and it has implemented the delegate method
	@try
	{
		if([delegate respondsToSelector:@selector(iTunesForeignInfo:didFindConnectionForITunesTrack:)])
		{
			int trackID = [[track objectForKey:TRACK_ID] intValue];
			ITunesTrack *track = [self iTunesTrackForID:trackID];
			
			[delegate iTunesForeignInfo:self didFindConnectionForITunesTrack:track];
		}
	}
	@catch(NSException *error)
	{
		// An exception may be possible above due to threading issues.
		NSLog(@"Caught exception: %@", error);
		
		// If this happens, make sure it doesn't happen again.
		delegate = nil;
	}
}

@end
