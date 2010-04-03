#import "ITunesForeignData.h"

@interface ITunesForeignData (PrivateAPI)
- (void)setupConnections;
@end


@implementation ITunesForeignData

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes the iTunesData and iTunesForeignData.
 * The iTunesData is initialized using the given path to an iTunes Music Library xml file.
 * 
 * Note: Since this method initializes the iTunesData, it may take several seconds to complete.
**/
- (id)initWithXMLPath:(NSString *)xmlPath
{
	if((self = [super initWithXMLPath:xmlPath]))
	{
		// Nothing to do here...
	}
	return self;
}

/**
 * Initializes iTunesData, and iTunesForeignData.
 * The iTunesData is initialized using the given data containing an iTunes Music Library xml file.
 *
 * Note: Since this method initializes the iTunesData, it may take several seconds to complete.
**/
- (id)initWithXMLData:(NSData *)xmlData
{
	if((self = [super initWithXMLData:xmlData]))
	{
		// Nothing to do here...
	}
	return self;
}

/**
 * Releases all memory associated with this class instance.
**/
- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	[super dealloc];
}

// DELEGATE SUPPORT
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)delegate
{
	return delegate;
}

- (void)setDelegate:(id)newDelegate
{
	delegate = newDelegate;
}

// CONNECTIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Immediately calculates the connections between this library, and the local iTunes library.
 * The thread calling this method will halt until the analysis is complete.
**/
- (void)calculateConnections
{
	[self setupConnections];
}

/**
 * Calculates the connections between this library, and the local iTunes library.
 * The analysis is done in a background thread, which allows the calling thread to remain responsive.
**/
- (void)calculateConnectionsInBackground
{
	[NSThread detachNewThreadSelector:@selector(setupConnections) toTarget:self withObject:nil];
}

/**
 * Calculates connections between the songs in this object instance and the local iTunes library.
 * This method may be run in the current thread, or as a background thread.
**/
- (void)setupConnections
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Initialize dictionary to map an artist to all the tracks with that artist
	NSMutableDictionary *artists  = [NSMutableDictionary dictionary];
	
	NSEnumerator *enumerator = [[self tracks] objectEnumerator];
	NSMutableDictionary *currentTrack;
	
	while((currentTrack = [enumerator nextObject]))
	{
		// Note: We convert to lowercase, because we don't want to be case sensitive
		NSString *currentArtist = [[currentTrack objectForKey:TRACK_ARTIST] lowercaseString];
		if(currentArtist == nil)
			currentArtist = @"";
		
		NSMutableArray *artistsArray = [artists objectForKey:currentArtist];
		if(artistsArray == nil)
		{
			artistsArray = [NSMutableArray arrayWithCapacity:1];
			[artists setObject:artistsArray forKey:currentArtist];
		}
		[artistsArray addObject:[currentTrack objectForKey:TRACK_ID]];
	}
	
	// Get the local iTunes library data
	ITunesData *localData = [ITunesData allLocalITunesData];
	
	// Loop through all the local tracks
	NSEnumerator *localEnumerator = [[localData tracks] objectEnumerator];
	NSDictionary *currentLocalTrack;
	
	while((currentLocalTrack = [localEnumerator nextObject]))
	{
		// Note: We convert to lowercase, because we don't want to be case sensitive
		NSString *currentLocalArtist = [[currentLocalTrack objectForKey:TRACK_ARTIST] lowercaseString];
		if(currentLocalArtist == nil)
			currentLocalArtist = @"";
		
		NSArray *songsBySameArtist = [artists objectForKey:currentLocalArtist];
		if(songsBySameArtist != nil)
		{
			NSString *currentLocalName = [currentLocalTrack objectForKey:TRACK_NAME];
			
			uint i;
			for(i = 0; i < [songsBySameArtist count]; i++)
			{
				int trackID = [[songsBySameArtist objectAtIndex:i] intValue];
				currentTrack = [self trackForID:trackID];
				
				NSString *currentName = [currentTrack objectForKey:TRACK_NAME];
				
				if([currentName caseInsensitiveCompare:currentLocalName] == NSOrderedSame)
				{
					[self addConnectionBetweenTrack:currentTrack andLocalTrack:currentLocalTrack];
				}
			}
		}
	}
    
	[pool release];
}

/**
 * This method adds a connection between a track (in the foreign data) and a local track.
 * This method be be overriden by other classes to provide extra features, notifications, delegate support, etc.
**/
- (void)addConnectionBetweenTrack:(NSMutableDictionary *)track andLocalTrack:(NSDictionary *)localTrack
{
	// Add connection to track
	[track setObject:[localTrack objectForKey:TRACK_ID] forKey:TRACK_CONNECTION];
	
	// Invoke delegate method if a delegate is set, and it has implemented the delegate method
	@try
	{
		if([delegate respondsToSelector:@selector(iTunesForeignData:didFindConnectionForTrack:)])
		{
			[delegate iTunesForeignData:self didFindConnectionForTrack:track];
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
