#import "ITunesData.h"
#import "RHDate.h"
#import "RHAliasHandler.h"
#import "RHMutableDictionary.h"

#ifdef TARGET_MOJO_HELPER
  #import "MojoDefinitions.h"
#endif

#ifdef TARGET_MOJO
  #import "MojoAppDelegate.h"
  #import "HelperProtocol.h"
#endif

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

@interface ITunesData (PrivateAPI)
- (void)performPostInitSetup;
- (void)addChildrenToPlaylist:(NSMutableDictionary *)playlist;
- (NSMutableArray *)sortPlaylists:(NSArray *)unsortedPlaylists;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ITunesData

static ITunesData *localITunesData;
static NSTimer *releaseTimer;
static NSDate *modDate;
static NSLock *lock;

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		
		lock = [[NSLock alloc] init];
	}
}

/**
 * Retrieves the shared instance of the data for the local iTunes library, containing all tracks and playlists.
 * This method automatically updates the local shared instance if the XML file has been updated on disk.
 * 
 * This method is thread safe.
**/
+ (ITunesData *)allLocalITunesData
{
	// This method is often called in a background thread
	// Thus we use synchronization methods
	[lock lock];
	
	// Get path to local iTunes Music Library data
	NSString *localXMLPath = [self localITunesMusicLibraryXMLPath];
	
	// Get modification date of xml file
	NSDictionary *atr  = [[NSFileManager defaultManager] fileAttributesAtPath:localXMLPath traverseLink:NO];
	NSDate *newModDate = [atr objectForKey:NSFileModificationDate];
	
	if(localITunesData == nil || [newModDate isLaterDate:modDate])
	{
		[localITunesData release];
		localITunesData = [[ITunesData alloc] initWithXMLPath:localXMLPath];
		
		// Store modification date
		[modDate release];
		modDate = [newModDate retain];
	}
	
	// Remember: Timer MUST be scheduled on main thread
	[self performSelectorOnMainThread:@selector(scheduleReleaseTimer) withObject:nil waitUntilDone:NO];
	
	// Since the value is constantly being updated, the value must be
	// first retained, and then autoreleased before it is returned to the calling method.
	// This ensures it won't disappear on the calling method while it is being used.
	ITunesData *result = [[localITunesData retain] autorelease];
	
	[lock unlock];
	
	return result;
}

/**
 * This method MUST be run on the main thread.
 * Timers are added to the run loop of the current thread.
 * Calling this method on a short-lived background thread will result in the timer never firing.
**/
+ (void)scheduleReleaseTimer
{
	// Cancel the release timer if it is active
	if(releaseTimer)
	{
		[releaseTimer invalidate];
		[releaseTimer release];
		releaseTimer = nil;
	}
	
	// Start a new timer to release the data after a period of time to help free memory
	releaseTimer = [[NSTimer scheduledTimerWithTimeInterval:(60 * 5)
													 target:self
												   selector:@selector(releaseLocalITunesData:)
												   userInfo:nil
													repeats:NO] retain];
}

+ (void)releaseLocalITunesData:(NSTimer *)aTimer
{
	[self flushAllLocalITunesData];
}

+ (void)flushAllLocalITunesData
{
	[lock lock];
	
	[localITunesData release];
	localITunesData = nil;
	
	[releaseTimer release];
	releaseTimer = nil;
	
	[lock unlock];
}

/**
 * Returns the location of the local "iTunes Music Library.xml" file.
 * The location of the file is searched for, automatically resolving Mac aliases.
 * In order to do this, it follows the same search pattern that iTunes follows.
 * Most of the logic behind this search is based on the information from here:
 * http://www.indyjt.com/blog/?p=51
**/
+ (NSString *)localITunesMusicLibraryXMLPath
{
#ifdef TARGET_MOJO_HELPER
	NSString *configuredPath = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_ITUNES_LOCATION];
#endif
	
#ifdef TARGET_MOJO
	NSString *configuredPath = [[[NSApp delegate] helperProxy] iTunesLocation];
#endif
	
	if(configuredPath && [[NSFileManager defaultManager] fileExistsAtPath:configuredPath])
	{
		return configuredPath;
	}
	else
	{
		// We need to search for the location of the XML file
		NSString *xmlPath1 = [@"~/Music/iTunes/iTunes Music Library.xml" stringByExpandingTildeInPath];
		NSString *xmlPath2 = [@"~/Documents/iTunes/iTunes Music Library.xml" stringByExpandingTildeInPath];
		NSArray *locations = [NSArray arrayWithObjects:xmlPath1, xmlPath2, nil];
		
		int i;
		for(i = 0; i < [locations count]; i++)
		{
			NSString *xmlPath = [RHAliasHandler resolvePath:[locations objectAtIndex:i]];
			
			if([[NSFileManager defaultManager] fileExistsAtPath:xmlPath])
			{
				return xmlPath;
			}
		}
		
		return nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard init methods are not allowed.
 * This class must be initialized with initWithXMLPath: or initWithXMLData:
**/
- (id)init
{
	[self release];
	return nil;
}

- (id)initWithXMLPath:(NSString *)xmlPath
{
	if((self = [super init]))
	{
		// Load iTunes Music Library plist
		library = [[NSMutableDictionary alloc] initWithContentsOfFile:xmlPath];
		
		if(library == nil)
		{
			[self release];
			return nil;
		}
		
		[self performPostInitSetup];
	}
	return self;
}

- (id)initWithXMLData:(NSData *)xmlData
{
	if((self = [super init]))
	{
		// Load iTunes Music Library plist
		library = [[NSMutableDictionary alloc] initWithData:xmlData];
		
		if(library == nil)
		{
			[self release];
			return nil;
		}
		
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Releases all memory associated with this class instance.
 * This is mostly the iTunes library dictionary, which can be rather large.
**/
- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
	[library release];
	[playlistMappings release];
	[playlistHeirarchy release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Post-Processing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)performPostInitSetup
{
	NSArray *allPlaylists = [self playlists];
	
	playlistMappings = [[NSMutableDictionary alloc] initWithCapacity:[allPlaylists count]];
	
	unsigned int i;
	for(i = 0; i < [allPlaylists count]; i++)
	{
		NSMutableDictionary *playlist = [allPlaylists objectAtIndex:i];
		
		// Set playlist type
		
		if([playlist objectForKey:@"Master"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_MASTER] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Music"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_MUSIC] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Movies"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_MOVIES] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"TV Shows"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_TVSHOWS] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Podcasts"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_PODCASTS] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Videos"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_VIDEOS] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Audiobooks"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_AUDIOBOOKS] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Purchased Music"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_PURCHASED] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Party Shuffle"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_PARTYSHUFFLE] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Folder"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_FOLDER] forKey:PLAYLIST_TYPE];
		}
		else if([playlist objectForKey:@"Smart Info"] != nil)
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_SMART] forKey:PLAYLIST_TYPE];
		}
		else
		{
			[playlist setObject:[NSNumber numberWithInt:PLAYLIST_TYPE_NORMAL] forKey:PLAYLIST_TYPE];
		}
		
		// Add playlist mapping
		
		NSString *playlistPersistentID = [playlist objectForKey:PLAYLIST_PERSISTENTID];
		if(playlistPersistentID)
		{
			[playlistMappings setObject:playlist forKey:playlistPersistentID];
		}
		
		// Add playlist children
		
		[self addChildrenToPlaylist:playlist];
	}
	
	// Create playlist heirarchy
	
	NSMutableArray *unsortedPlaylistHeirarchy = [NSMutableArray arrayWithCapacity:25];
	
	for(i = 0; i < [allPlaylists count]; i++)
	{
		NSMutableDictionary *playlist = [allPlaylists objectAtIndex:i];
		
		if([playlist objectForKey:PLAYLIST_PARENT_PERSISTENTID] == nil)
		{
			[unsortedPlaylistHeirarchy addObject:playlist];
		}
	}
	
	playlistHeirarchy = [[self sortPlaylists:unsortedPlaylistHeirarchy] retain];
}

- (void)addChildrenToPlaylist:(NSMutableDictionary *)playlist
{
	unsigned int i;
	NSMutableArray *allPlaylists = [self playlists];
	
	NSString *playlistPersistentID = [playlist objectForKey:PLAYLIST_PERSISTENTID];
	
	if(playlistPersistentID == nil) return;
	
	// Figure out the children
	// This isn't that hard, because all child playlists have a "Parent Persistet ID"
	
	NSMutableArray *unsortedChildren = [NSMutableArray arrayWithCapacity:1];
	
	for(i = 0; i < [allPlaylists count]; i++)
	{
		NSMutableDictionary *currentPlaylist = [allPlaylists objectAtIndex:i];
		
		if([playlistPersistentID isEqualToString:[currentPlaylist objectForKey:PLAYLIST_PARENT_PERSISTENTID]])
		{
			[unsortedChildren addObject:currentPlaylist];
		}
	}
	
	if([unsortedChildren count] == 0) return;
	
	// Sort the children
	
	NSMutableArray *sortedChildren = [self sortPlaylists:unsortedChildren];
	
	// Store list of children in playlist
	// The list will be an array of persistent ID's
	
	NSMutableArray *children = [NSMutableArray arrayWithCapacity:[sortedChildren count]];
	
	for(i = 0; i < [sortedChildren count]; i++)
	{
		NSDictionary *currentPlaylist = [sortedChildren objectAtIndex:i];
		
		[children addObject:[currentPlaylist objectForKey:PLAYLIST_PERSISTENTID]];
	}
	
	[playlist setObject:children forKey:PLAYLIST_CHILDREN];
}

- (NSMutableArray *)sortPlaylists:(NSArray *)unsortedPlaylists
{
	unsigned int i, j;
	
	// Sorting is kept simplified because of 2 reasons:
	// 1: iTunes keeps the playlists in the XML file sorted alphabetically
	// 2. The type field is an integer, and lower values correspond to a higher order in the source table
	
	NSMutableArray *sortedPlaylists = [NSMutableArray arrayWithCapacity:[unsortedPlaylists count]];
	
	for(i = 0; i < [unsortedPlaylists count]; i++)
	{
		NSMutableDictionary *playlist = [unsortedPlaylists objectAtIndex:i];
		int playlistType = [[playlist objectForKey:PLAYLIST_TYPE] intValue];
		
		int index = 0;
		BOOL found = NO;
		
		for(j = 0; j < [sortedPlaylists count] && !found; j++)
		{
			if(playlistType < [[[sortedPlaylists objectAtIndex:j] objectForKey:PLAYLIST_TYPE] intValue])
				found = YES;
			else
				index++;
		}
		
		[sortedPlaylists insertObject:playlist atIndex:index];
	}
	
	return sortedPlaylists;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Data Extraction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the persistent ID for the iTunes music library.
**/
- (NSString *)libraryPersistentID
{
	return [library objectForKey:LIBRARY_PERSISTENTID];
}


/**
 * Returns the music folder location for the iTunes music library.
 * This will be in a URL format, just like the location of songs.
**/
- (NSString *)musicFolder
{
	return [library objectForKey:MUSIC_FOLDER];
}

/**
 * Returns dictionary of tracks.
 * 
 * Each key in the dictionary is a track ID.
 * Each valud in the dictionary is a track dictionary.
 * Use the defined TRACK_X strings as keys to the track dictionary (eg TRACK_NAME).
**/
- (NSMutableDictionary *)tracks
{
	return [library objectForKey:@"Tracks"];
}

/**
 * Returns array of playlist dictionaries.
 *
 * Each object in the array is an NSMutableDictionary, which contains info for that particular playlist.
 * Each playlist dictionary contains the following keys (among others):
 *   Name - Name of playlist
 *   Playlist Items - Array of dictionaries, with each dictionary containing a track ID number.
**/
- (NSMutableArray *)playlists
{
	return [library objectForKey:@"Playlists"];
}

/**
 * Returns an array of top-level playlists.
 * 
 * You can get a playlist's children with the PLAYLIST_CHILDREN key.
 * This returns an array of playlist persistent ids.
 * Use the playlistForPersistentID method to get the child playlist dictionary.
 * 
 * Each object in the array is an NSMutableDictionary, which contains info for that particular playlist.
 * Each playlist dictionary contains the following keys (among others):
 *   Name - Name of playlist
 *   Playlist Items - Array of dictionaries, with each dictionary containing a track ID number.
**/
- (NSMutableArray *)playlistHeirarchy
{
	return playlistHeirarchy;
}

/**
 * Returns the playlist dictionary for the given index (in the array)
 * 
 * Same as [[data playlists] objectAtIndex:playlistIndex]
 * Here as a convenience method to make code look prettier and more understandable.
 * 
 * @param playlistIndex - The index of the desired playlist, in the array of playlists.
**/
- (NSMutableDictionary *)playlistForIndex:(int)playlistIndex
{
	NSMutableArray *playlists = [self playlists];
	
	if(playlistIndex < [playlists count])
		return [playlists objectAtIndex:playlistIndex];
	else
		return nil;
}

/**
 * Returns the playlist dictionary for the given playlist persistent ID.
**/
- (NSMutableDictionary *)playlistForPersistentID:(NSString *)persistentID
{
	return [playlistMappings objectForKey:persistentID];
}


/**
 * Returns the master playlist, which includes every track in the iTunes library.
 *
 * This is a convenience method (for readability), and returns the same thing
 * as [data playlistForIndex:0], since the first playlist is always the master playlist.
**/
- (NSMutableDictionary *)masterPlaylist
{
	return [self playlistForIndex:0];
}


/**
 * Returns the dictionary for the given track index.
 * 
 * Each track dictionary contains the following keys (among others):
 *   Name - Name of song (IE - Your Body is a Wonderland)
 *   Artist - Name of artist (IE - John Mayer)
 *   Album - Name of album track is from (IE - Room For Squares)
 *   Total Time - Number of milliseconds in song
 *   Location - File URL
 * 
 * @param trackID - The ID of the desired track in the XML database.
**/
- (NSMutableDictionary *)trackForID:(int)trackID
{
	NSString *key = [[NSString alloc] initWithFormat:@"%i",trackID];
	
	NSMutableDictionary *result = [[self tracks] objectForKey:key];
	
	[key release];
	return result;
}


/**
 * Returns the total number of tracks in the iTunes library.
 * This is the same as getting the count from the master playlist.
**/
- (int)numberOfTracks
{
	return [[self tracks] count];
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Validation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/**
 * Returns the proper trackID for the given persistentID.
 *
 * Track ID's are not persistent across multiple creations of the "iTunes Music Library.xml" file from iTunes.
 * Thus storing the trackID will not guarantee the same song will be played upon the next XML parse.
 * Luckily apple provides a persistentID which may be used to lookup a song across multiple XML parses.
 * However, the trackID is the key in which to lookup the song, so it is more or less necessary.
 *
 * This method provides a means with which to map a persistentID to it's corresponding trackID.
 * The trackID which is assumed to be correct is passed along with it.
 * This helps, because often times it is correct, and thus a search may be avoided.
 * 
 * @param trackID - The old trackID that was used for the song with this persistentID.
 * @param persistentTrackID - This is the persistentID for the song, which doesn't change between XML parses.
 * 
 * @return The trackID that currently corresponds to the given persistentID, or -1 if the persistentID was not found.
**/
- (int)validateTrackID:(int)trackID withPersistentTrackID:(NSString *)persistentTrackID
{
	// Ignore the validation request if the persistentTrackID is nil (uninitialized)
	if(persistentTrackID == nil)
	{
		return trackID;
	}
	
	// Get the track for the specified trackID
	NSDictionary *dict = [self trackForID:trackID];
	
	// Does the persistentID match the one given
	if((dict != nil) && [[dict objectForKey:TRACK_PERSISTENTID] isEqualToString:persistentTrackID])
	{
		// It's a match, so just return the original trackID
		return trackID;
	}
	
	// The trackID has changed!
	// Now we have to loop through the tracks, and find the one with the correct persistentID
	NSEnumerator *enumerator = [[self tracks] objectEnumerator];
	NSDictionary *currentTrack;
	BOOL found = NO;
		
	while(!found && (currentTrack = [enumerator nextObject]))
	{
		found = [[currentTrack objectForKey:TRACK_PERSISTENTID] isEqualToString:persistentTrackID];
	}
	
	if(found)
		return [[currentTrack objectForKey:TRACK_ID] intValue];
	else
		return -1;
}


/**
 * Returns the proper playlistIndex for the given persistentID.
 * 
 * A Playlist Index is not persistent across multiple creations of the "iTunes Music Library.xml" file from iTunes.
 * Thus storing the playlist index will not guarantee the same playlist will be played upon the next XML parse.
 * Luckily apple provides a persistentID which may be used to lookup a playlist across multiple XML parses.
 * However, the playlist index is needed to lookup the playlist, so it is more or less necessary.
 * 
 * This method provides a means with which to map a persistentID to it's corresponding index.
 * The playlist index which is assumed to be correct is passed along with it.
 * This helps, because often times it is correct, and thus a search may be avoided.
 * 
 * @param playlistIndex - The old playlist index that was used for the playlist with this persistentID.
 * @param persistentPlaylistID - This is the persistentID for the playlist, which doesn't change between XML parses.
 * 
 * @return The index that currently corresponds to the given persistentID, or -1 if the persistentID was not found.
**/
- (int)validatePlaylistIndex:(int)playlistIndex withPersistentPlaylistID:(NSString *)persistentPlaylistID;
{
	// Ignore the validation request if the persistentPlaylistID is nil (uninitialized)
	if(persistentPlaylistID == nil)
	{
		return playlistIndex;
	}
	
	// Get the playlist for the specified playlistID
	NSDictionary *dict = [self playlistForIndex:playlistIndex];
	
	// Does the persistentID match the one given
	if((dict != nil) && [[dict objectForKey:PLAYLIST_PERSISTENTID] isEqualToString:persistentPlaylistID])
	{
		// It's a match, so just return the original playlistIndex
		return playlistIndex;
	}
	
	// The playlistID has changed!
	// Now we have to loop through the playlists, and find the one with the correct persistentID
	int i = 0;
	BOOL found = NO;
	NSArray *playlists = [self playlists];
	
	while(!found && (i < [playlists count]))
	{
		if([persistentPlaylistID isEqualToString:[[playlists objectAtIndex:i] objectForKey:PLAYLIST_PERSISTENTID]])
			found = YES;
		else
			i++;
	}
	
	if(found)
		return i;
	else
		return -1;
}

@end