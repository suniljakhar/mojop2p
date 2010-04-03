#import <Cocoa/Cocoa.h>
#import "ITunesLocalSharedData.h"
#import "RHDate.h"

#ifdef TARGET_MOJO_HELPER
  #import "MojoDefinitions.h"
#endif

#ifdef TARGET_MOJO
  #import "MojoAppDelegate.h"
#endif

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#define TRACK_SHARED       @"DD:Shared"
#define PLAYLIST_INDEX     @"DD:Index"

@interface ITunesLocalSharedData (PrivateAPI)
- (void)filterTracksAndPlaylists;
- (void)filterUnneededInformation;
@end


@implementation ITunesLocalSharedData

// CLASS VARIABLES AND METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ITunesLocalSharedData *localITunesData;
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

+ (ITunesData *)allLocalITunesData
{
	// Prevent potential problems
	[NSException raise:@"NotAllowed" format:@"Method +allLocalITunesData must be called via ITunesData class!"];
	
	return nil;
}

/**
 * Retrieves the shared instance of the data for the local iTunes library, containing only shared tracks and playlists.
 * This method automatically updates the local shared instance if the XML file has been updated on disk.
 * 
 * This method is thread safe.
**/
+ (ITunesLocalSharedData *)sharedLocalITunesData
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
		localITunesData = [[ITunesLocalSharedData alloc] initWithXMLPath:localXMLPath];
		
		// Store modification date
		[modDate release];
		modDate = [newModDate retain];
	}
	
	// Remember: Timer MUST be scheduled on main thread
	[self performSelectorOnMainThread:@selector(scheduleReleaseTimer) withObject:nil waitUntilDone:NO];
	
	// Since the value is constantly being updated, the value must be
	// first retained, and then autoreleased before it is returned to the calling method.
	// This ensures it won't disappear on the calling method while it is being used.
	ITunesLocalSharedData *result = [[localITunesData retain] autorelease];
	
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
												   selector:@selector(releaseSharedLocalITunesData:)
												   userInfo:nil
													repeats:NO] retain];
}

+ (void)releaseSharedLocalITunesData:(NSTimer *)aTimer
{
	[self flushSharedLocalITunesData];
}

+ (void)flushSharedLocalITunesData
{
	[lock lock];
	
	[localITunesData release];
	localITunesData = nil;
	
	[releaseTimer release];
	releaseTimer = nil;
	
	[lock unlock];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	[self release];
	return nil;
}

- (id)initWithXMLPath:(NSString *)xmlPath
{
	if((self = [super initWithXMLPath:xmlPath]))
	{
		[self filterTracksAndPlaylists];
		[self filterUnneededInformation];
	}
	return self;
}

- (id)initWithXMLData:(NSData *)xmlData
{
	if((self = [super initWithXMLData:xmlData]))
	{
		[self filterTracksAndPlaylists];
		[self filterUnneededInformation];
	}
	return self;
}

- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Filtering
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)filterTracksAndPlaylists
{
#ifdef TARGET_MOJO_HELPER
	BOOL isFiltering = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_SHARE_FILTER];
#else
	BOOL isFiltering = [[[NSApp delegate] helperProxy] isSharingFilterEnabled];
#endif
	
	if(!isFiltering) return;
	
	// What needs to happen:
	// 1 - Remove all tracks not included in shared playlists
	// 2 - Set proper state for all playlists
	// 3 - Update folder playlists with NSMixedState
	
#ifdef TARGET_MOJO_HELPER	
	NSArray *sharedPlaylists = [[NSUserDefaults standardUserDefaults] arrayForKey:PREFS_SHARED_PLAYLISTS];
#else
	NSArray *sharedPlaylists = [[[NSApp delegate] helperProxy] sharedPlaylists];
#endif
	
	unsigned int i;
	
	// Loop through every shared playlist, and set its state to NSOnState.
	// Then loop through every track in the shared playlist, and make a note that it should be included.
	
	for(i = 0; i < [sharedPlaylists count]; i++)
	{
		NSDictionary *plistInfo = [sharedPlaylists objectAtIndex:i];
		NSString *persistentID = [plistInfo objectForKey:PLAYLIST_PERSISTENTID];
		
		NSMutableDictionary *playlist = [self playlistForPersistentID:persistentID];
		
		[self setState:NSOnState ofPlaylist:playlist];
		
		NSEnumerator *enumerator = [[playlist objectForKey:PLAYLIST_ITEMS] objectEnumerator];
		NSDictionary *trackDict;
		
		while((trackDict = [enumerator nextObject]))
		{
			int trackID = [[trackDict objectForKey:TRACK_ID] intValue];
			
			[[self trackForID:trackID] setObject:[NSNumber numberWithBool:YES] forKey:TRACK_SHARED];
		}
	}
	
	// At this point, every track that should be shared has a TRACK_SHARED key.
	// Now we just need to remove every track that doesn't have this key.
	
	NSArray *values = [[self tracks] allValues];
	
	for(i = 0; i < [values count]; i++)
	{
		NSMutableDictionary *currentTrack = [values objectAtIndex:i];
		
		if(![[currentTrack objectForKey:TRACK_SHARED] boolValue])
		{
			NSString *key = [[NSString alloc] initWithFormat:@"%@", [currentTrack objectForKey:TRACK_ID]];
			
			[[self tracks] removeObjectForKey:key];
			
			[key release];
		}
	}
	
	// At this point every unshared track has been removed from the master tracks hashtable.
	
	// Now we need to remove any playlists that aren't shared.
	// Master playlists (such as Music, Movies, etc) don't get removed.
	// 
	// We also need to remove any references to tracks that aren't shared.
	
	NSMutableArray *allPlaylists = [self playlists];
	
	int j, k; // Note: This must be int, not uint, because we need it to go to -1
	
	for(j = [allPlaylists count] - 1; j >= 0; j--)
	{
		NSMutableDictionary *playlist = [allPlaylists objectAtIndex:j];
		int state = [[playlist objectForKey:PLAYLIST_STATE] intValue];
		
		if(state == NSOffState)
		{
			int type = [[playlist objectForKey:PLAYLIST_TYPE] intValue];
			
			if(type <= PLAYLIST_TYPE_AUDIOBOOKS)
			{
				// Master playlist - remove all tracks that aren't shared
				NSMutableArray *tracks = [playlist objectForKey:PLAYLIST_ITEMS];
				
				for(k = [tracks count] - 1; k >= 0; k--)
				{
					NSDictionary *track = [tracks objectAtIndex:k];
					int trackID = [[track objectForKey:TRACK_ID] intValue];
					
					if([self trackForID:trackID] == nil)
					{
						[tracks removeObjectAtIndex:k];
					}
				}
			}
			else
			{
				// Remove all tracks from the playlist (to reduce memory footprint)
				[playlist removeObjectForKey:PLAYLIST_ITEMS];
				
				// Remove playlist since it isn't shared
				[[self playlists] removeObjectAtIndex:j];
				
				// Remember: The playlist won't be deallocated because it's still retained by the playlist mappings.
			}
		}
	}
}

/**
 * Removes all keys from the tracks that aren't needed.
 * This helps to reduce the size of the plist.
**/
- (void)filterUnneededInformation
{
	NSArray *unNeededKeys = [NSArray arrayWithObjects:TRACK_SHARED,
	                                                  @"File Folder Count",
		                                              @"Library Folder Count",
		                                              @"Album Rating",
		                                              @"Album Rating Computed",
		                                              @"Date Modified",
		                                              @"Play Date",
		                                              @"Play Date UTC", nil];
		
	NSEnumerator *enumerator = [[self tracks] objectEnumerator];
	NSMutableDictionary *currentTrack;
	
	while((currentTrack = [enumerator nextObject]))
	{
		[currentTrack removeObjectsForKeys:unNeededKeys];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Toggling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Recursively sets that state of the playlist, and all child playlists, to the given state
 * which should be either NSOnState or NSOffState.
**/
- (void)recurseDownWithPlaylist:(NSMutableDictionary *)playlist state:(int)state
{
	[playlist setObject:[NSNumber numberWithInt:state] forKey:PLAYLIST_STATE];
	
	NSArray *children = [playlist objectForKey:PLAYLIST_CHILDREN];
	
	int i;
	for(i = 0; i < [children count]; i++)
	{
		NSString *childPlaylistPersistentID = [children objectAtIndex:i];
		NSMutableDictionary *childPlaylist = [self playlistForPersistentID:childPlaylistPersistentID];
		
		[self recurseDownWithPlaylist:childPlaylist state:state];
	}
}

/**
 * Recursively sets the state of the playlist, and all parent playlists, to the appropriate state,
 * which is either NSOnState, NSOffState or NSMixedState, depending upon the state of all children.
**/
- (void)recurseUpWithPlaylist:(NSMutableDictionary *)playlist state:(int)state
{
	NSArray *children = [playlist objectForKey:PLAYLIST_CHILDREN];
	
	BOOL allChildrenSameState = YES;
	
	int i;
	for(i = 0; i < [children count]; i++)
	{
		NSString *childPlaylistPersistentID = [children objectAtIndex:i];
		NSMutableDictionary *childPlaylist = [self playlistForPersistentID:childPlaylistPersistentID];
		
		int childState = [[childPlaylist objectForKey:PLAYLIST_STATE] intValue];
		
		if(childState != state)
		{
			allChildrenSameState = NO;
		}
	}
	
	if(allChildrenSameState)
		[playlist setObject:[NSNumber numberWithInt:state] forKey:PLAYLIST_STATE];
	else
		[playlist setObject:[NSNumber numberWithInt:NSMixedState] forKey:PLAYLIST_STATE];
	
	NSString *parentPersistentID = [playlist objectForKey:PLAYLIST_PARENT_PERSISTENTID];
	NSMutableDictionary *parentPlaylist = [self playlistForPersistentID:parentPersistentID];
	
	if(parentPlaylist)
	{
		[self recurseUpWithPlaylist:parentPlaylist state:state];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setState:(int)state ofPlaylist:(NSMutableDictionary *)playlist
{
	if(state == NSOnState)
	{
		// All subplaylists need to change to NSOnState.
		// All superplaylist need to change to either NSOnState or NSMixedState.
		
		[self recurseDownWithPlaylist:playlist state:NSOnState];
		[self recurseUpWithPlaylist:playlist state:NSOnState];
	}
	else
	{
		// All subplaylists need to change to NSOffState.
		// All superplaylists need to change to either NSOffState or NSMixedState.
		
		[self recurseDownWithPlaylist:playlist state:NSOffState];
		[self recurseUpWithPlaylist:playlist state:NSOffState];
	}
	
	// Note: The given playlist's state is updated in the recurse methods
}

- (void)toggleStateOfPlaylist:(NSMutableDictionary *)playlist
{
	int state = [[playlist objectForKey:PLAYLIST_STATE] intValue];
	
	if(state == NSOffState)
	{
		[self setState:NSOnState ofPlaylist:playlist];
	}
	else
	{
		[self setState:NSOffState ofPlaylist:playlist];
	}
}

- (void)saveChanges
{
	NSMutableArray *sharedPlaylists = [NSMutableArray arrayWithCapacity:10];
	
	// The library only contains those playlists that were originally shared when this instance was created.
	// But we can still access the full list of playlists via playlistMappings.
	
	NSEnumerator *playlistEnumerator = [playlistMappings objectEnumerator];
	NSDictionary *playlist;
	
	while ((playlist = [playlistEnumerator nextObject]))
	{
		int state = [[playlist objectForKey:PLAYLIST_STATE] intValue];
		
		if(state == NSOnState)
		{
			NSString *name = [playlist objectForKey:PLAYLIST_NAME];
			NSString *persistentID = [playlist objectForKey:PLAYLIST_PERSISTENTID];
			
			NSDictionary *plistInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									   name, PLAYLIST_NAME,
									   persistentID, PLAYLIST_PERSISTENTID, nil];
			
			[sharedPlaylists addObject:plistInfo];
		}
	}
	
#ifdef TARGET_MOJO_HELPER
	[[NSUserDefaults standardUserDefaults] setObject:sharedPlaylists forKey:PREFS_SHARED_PLAYLISTS];
#else
	[[[NSApp delegate] helperProxy] setSharedPlaylists:sharedPlaylists];
#endif
}

- (NSData *)serializedData
{
	// We've got an ugly hack here.
	// Older versions of Mojo for Windows can't parse the serializedData that we would normally create here,
	// because they relied on the tracks coming before the playlists in the XML file.
	// This causes these programs to crash.
	// So until most people upgrade to the newer version, we've got this workaround in place.
	
#ifdef TARGET_MOJO_HELPER
	BOOL isFiltering = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_SHARE_FILTER];
	
	if(!isFiltering)
	{
		NSString *xmlPath = [ITunesData localITunesMusicLibraryXMLPath];
		
		return [NSData dataWithContentsOfFile:xmlPath options:NSUncachedRead error:nil];
	}
	
#endif
	
	return [NSPropertyListSerialization dataFromPropertyList:library
													  format:NSPropertyListXMLFormat_v1_0
											errorDescription:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)printPlaylists
{
	NSLog(@"----- Playlists -----");
	
	NSArray *allPlaylists = [self playlists];
	
	unsigned int i;
	for(i = 0; i < [allPlaylists count]; i++)
	{
		NSDictionary *currentPlaylist = [allPlaylists objectAtIndex:i];
		
		NSString *name = [currentPlaylist objectForKey:PLAYLIST_NAME];
		int state = [[currentPlaylist objectForKey:PLAYLIST_STATE] intValue];
		int numChildren = [[currentPlaylist objectForKey:PLAYLIST_ITEMS] count];
		
		NSLog(@"%@[%i] (%i)", name, state, numChildren);
	}
}

- (void)printPlaylistChildren:(NSDictionary *)playlist withIndentation:(int)level
{
	NSArray *children = [playlist objectForKey:PLAYLIST_CHILDREN];
	
	if([children count] == 0) return;
	
	NSMutableString *indent = [NSMutableString stringWithCapacity:(level * 2)];
	
	unsigned int i;
	for(i = 0; i < level; i++)
	{
		[indent appendString:@"  "];
	}
	
	for(i = 0; i < [children count]; i++)
	{
		NSString *childPlaylistPersistentID = [children objectAtIndex:i];
		NSDictionary *childPlaylist = [self playlistForPersistentID:childPlaylistPersistentID];
		
		NSString *name = [childPlaylist objectForKey:PLAYLIST_NAME];
		int state = [[childPlaylist objectForKey:PLAYLIST_STATE] intValue];
		int numChildren = [[childPlaylist objectForKey:PLAYLIST_ITEMS] count];
		
		NSLog(@"%@%@[%i] (%i)", indent, name, state, numChildren);
		[self printPlaylistChildren:childPlaylist withIndentation:(level+1)];
	}
}

- (void)printPlaylistHeirarchy
{
	NSLog(@"----- Playlist Heirarchy -----");
	
	unsigned int i;
	for(i = 0; i < [playlistHeirarchy count]; i++)
	{
		NSDictionary *currentPlaylist = [playlistHeirarchy objectAtIndex:i];
		
		NSString *name = [currentPlaylist objectForKey:PLAYLIST_NAME];
		int state = [[currentPlaylist objectForKey:PLAYLIST_STATE] intValue];
		int numChildren = [[currentPlaylist objectForKey:PLAYLIST_ITEMS] count];
		
		NSLog(@"%@[%i] (%i)", name, state, numChildren);
		[self printPlaylistChildren:currentPlaylist withIndentation:1];
	}
}

@end
