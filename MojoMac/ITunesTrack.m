#import "ITunesTrack.h"

#import "ITunesData.h"
#import "ITunesForeignData.h"
#import "ITunesForeignInfo.h"


@implementation ITunesTrack

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSDictionary *)createTracksForData:(ITunesData *)data
{
	// Get the list of tracks from the master playlist
	// Each item in the array is a dictionary, with only one key - the track ID
	NSArray *tracks = [[data masterPlaylist] objectForKey:PLAYLIST_ITEMS];
	
	// Create dictionary to hold the result
	// This will be a dictionary full of iTunesTrack objects as values, and their trackID's as keys
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[tracks count]];
	
	// Create an enumerator to loop through the tracks
	// Enumerators are faster then a standard for loop with larger arrays
	NSEnumerator *enumerator = [tracks objectEnumerator];
	NSDictionary *currentTrackRef;
	
	while((currentTrackRef = [enumerator nextObject]))
	{
		int trackID = [[currentTrackRef objectForKey:TRACK_ID] intValue];
		ITunesTrack *track = [[[ITunesTrack alloc] initWithTrackID:trackID forData:data] autorelease];
		
		[result setObject:track forKey:[NSString stringWithFormat:@"%i", trackID]];
	}
	
	return result;
}

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithTrackID:(int)trackID forData:(ITunesData *)data
{
	if((self = [super init]))
	{
		// We don't bother retaining the the trackRef since this class is only used as a wrapper
		trackRef = [data trackForID:trackID];
	}
	return self;
}

- (void)dealloc
{
//	NSLog(@"Destroying self: %@", self);
	[super dealloc];
}

// COMPARING
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method compares two tracks.
 * Two tracks are considered the same if they have the same track ID.
 * It is assumed that they are from the same iTunes library.
**/
- (BOOL)isEqual:(id)anObject
{
	if([anObject isKindOfClass:[self class]])
	{
		return ([self trackID] == [anObject trackID]);
	}
	return NO;
}

// LOW-LEVEL DATA ACCESS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the low-level track dictionary.
 * This is the dictionary that would would get by calling trackForID: in ITunesData.
**/
- (NSDictionary *)trackRef
{
	return trackRef;
}

// READ ONLY VARIABLES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)persistentID {
	return [trackRef objectForKey:TRACK_PERSISTENTID];
}

- (NSString *)location {
	return [trackRef objectForKey:TRACK_LOCATION];
}

- (NSString *)name {
	return [trackRef objectForKey:TRACK_NAME];
}

- (NSString *)artist {
	return [trackRef objectForKey:TRACK_ARTIST];
}

- (NSString *)album {
	return [trackRef objectForKey:TRACK_ALBUM];
}

- (NSString *)genre {
	return [trackRef objectForKey:TRACK_GENRE];
}

- (NSString *)composer {
	return [trackRef objectForKey:TRACK_COMPOSER];
}

- (NSString *)kind {
	return [trackRef objectForKey:TRACK_KIND];
}

- (NSString *)type {
	return [trackRef objectForKey:TRACK_TYPE];
}

- (NSString *)comments {
	return [trackRef objectForKey:TRACK_COMMENTS];
}

- (NSDate *)dateAdded {
	return [trackRef objectForKey:TRACK_DATEADDED];
}

- (int)trackID {
	return [[trackRef objectForKey:TRACK_ID] intValue];
}

- (int)fileSize {
	return [[trackRef objectForKey:TRACK_FILESIZE] intValue];
}

- (int)totalTime {
	return [[trackRef objectForKey:TRACK_TOTALTIME] intValue];
}

- (int)playCount {
	return [[trackRef objectForKey:TRACK_PLAYCOUNT] intValue];
}

- (int)rating {
	return [[trackRef objectForKey:TRACK_RATING] intValue];
}

- (int)trackNumber {
	return [[trackRef objectForKey:TRACK_TRACKNUMBER] intValue];
}

- (int)trackCount {
	return [[trackRef objectForKey:TRACK_TRACKCOUNT] intValue];
}

- (int)discNumber {
	return [[trackRef objectForKey:TRACK_DISCNUMBER] intValue];
}

- (int)discCount {
	return [[trackRef objectForKey:TRACK_DISCCOUNT] intValue];
}

- (int)bitRate {
	return [[trackRef objectForKey:TRACK_BITRATE] intValue];
}

- (int)year {
	return [[trackRef objectForKey:TRACK_YEAR] intValue];
}

- (int)bpm {
	return [[trackRef objectForKey:TRACK_BPM] intValue];
}

- (NSString *)pathExtension
{
	NSString *pathExtension = [[self location] pathExtension];
	
	if([pathExtension length] > 0)
	{
		return pathExtension;
	}
	else
	{
		// No path extension on the file name!
		// We'll do some primitive checking to determine the file type.
		// Notice we're not trying very hard here.
		// This should be improved in the future if this happens often.
		
		NSString *kind = [self kind];
		
		if([kind hasPrefix:@"AAC"])
			return @"m4a";
		else
			return @"mp3";
	}
}

- (BOOL)isProtected
{
	if([[trackRef objectForKey:TRACK_ISPROTECTED] boolValue])
	{
		// Workaround for iTunes bug
		// In iTunes version 7.1 it was discovered that if you import a CD that already exists in iTunes, and
		// the version that exists in iTunes came from the iTunes music store, the newly imported version is 
		// marked as protected as well, even though it's obviously not.
		// To get around this bug, we check to see if the KIND indicates that it's protected as well.
		// We could also check the filename extension, but filename extensions are less reliable since they're optional.
		return [[self kind] hasPrefix:@"Protected"];
	}
	return NO;
}

- (BOOL)isVideo
{
	return [[trackRef objectForKey:TRACK_HASVIDEO] boolValue];
}

// MODIFIABLE VARIABLES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method returns true if a local connection has been discovered for this track.
 * The ITunesForeignData class may be used to search for, and record local connections.
 * Note that just because a connection is known, the specific connection may be unknown.
**/
- (BOOL)hasLocalConnection
{
	return ([self localTrackID] != 0);
}

/**
 * If flag if NO, any local connection will be deleted.
 * If flag is YES, and a local connection already exists, this method leaves the connection as is.
 * If flag is YES, and no local connection exists, an empty connection will be created.
**/
- (void)setHasLocalConnection:(BOOL)flag
{
	if(flag)
	{
		// Only create an empty connection if it doesn't already exist
		if(![self hasLocalConnection])
		{
			[trackRef setObject:[NSNumber numberWithInt:-1] forKey:TRACK_CONNECTION];
		}
	}
	else
		[trackRef setObject:[NSNumber numberWithInt:0] forKey:TRACK_CONNECTION];
}

/**
 * Returns the local track ID of the connection for this track.
 * If the track has no connection, this number will be zero.
 * If the track has a known connection, this number will be positive.
 * If the track has an unknown connection, this number will be negative.
**/
- (int)localTrackID {
	return [[trackRef objectForKey:TRACK_CONNECTION] intValue];
}
- (void)setLocalTrackID:(int)localTrackID
{
	[trackRef setObject:[NSNumber numberWithInt:localTrackID] forKey:TRACK_CONNECTION];
}

- (int)downloadStatus {
	return [[trackRef objectForKey:TRACK_DOWNLOADSTATUS] intValue];
}
- (void)setDownloadStatus:(int)downloadStatus
{
	[trackRef setObject:[NSNumber numberWithInt:downloadStatus] forKey:TRACK_DOWNLOADSTATUS];
}

@end
