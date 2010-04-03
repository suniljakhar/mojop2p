#import "ITunesPlayer.h"
#import "ITunesTrack.h"
#import "MojoAppDelegate.h"
#import "XMPPJID.h"

@interface ITunesPlayer (PrivateAPI)
- (void)setupQTMonitor;
- (void)teardownQTMonitor;
@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ITunesPlayer

/**
 * Initializes a new iTunes player, configured to connect directly to the host using the given base URL.
 * Corresponds to an MSWController created with initWithNetService: or initWithRemotePath: constructor.
**/
- (id)initWithBaseURL:(NSURL *)aBaseURL isGateway:(BOOL)flag
{
	if((self = [super init]))
	{
		// Store a copy of the base path
		baseURL = [aBaseURL copy];
		
		// If the base URL is pointing to a gateway server, make a note of it's port
		if(flag)
		{
			isOurGateway = NO;
			gatewayPort = [[baseURL port] intValue];
		}
		else
		{
			isOurGateway = NO;
			gatewayPort = 0;
		}
		
		// Configure status variables
		shouldPlay = NO;
		wasPlaying = NO;
		
		// Configure default volume
		volumePercentage = 1.0F;
		
		// Register for notifications
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(movieFinished:)
													 name:QTMovieDidEndNotification
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(movieLoadStateDidChange:)
													 name:QTMovieLoadStateDidChangeNotification
												   object:nil];
	}
	return self;
}

/**
 * Standard Deconstructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
	// Shut down the gateway server that MojoHelper created for us (if it's ours)
	if(isOurGateway)
	{
		[[[NSApp delegate] helperProxy] gateway_closeServerWithLocalPort:gatewayPort];
	}
	
	// Remove notification observers
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Remove any objects we created
	[baseURL release];
	[movie release];
	[currentTrack release];
	
	// Stop monitoring our movie
	// This also releases our timer
	[self teardownQTMonitor];
	
	// Move up the inheritance chain
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard delegate method.
 * Returns the current delegate for this instance.
**/
- (id)delegate
{
	return delegate;
}

/**
 * Standard setDelegate method.
 * Registers the given object as this instance's delegate.
**/
- (void)setDelegate:(id)newDelegate 
{
	delegate = newDelegate;
}

/**
 * QuickTime doesn't use callbacks for authentication.
 * Instead it relies on the standard URL loading mechanisms.
 * Thus, in order to prevent a QuickTime dialog box prompting the user for credentials,
 * the credentials must be set prior to playing a song. This method provides the means to do that.
**/
- (void)setUsername:(NSString *)username password:(NSString *)password
{
	// The standard way of setting up credentials for QuickTime is broken in Leopard!
	
	// Setup gateway server if we don't already have one
	if(gatewayPort == 0)
	{
		isOurGateway = YES;
		
		NSString *host = [baseURL host];
		UInt16 port = (UInt16)[[baseURL port] unsignedShortValue];
		
		gatewayPort = [[[NSApp delegate] helperProxy] gateway_openServerForHost:host port:port];
		
		// Create the new base URL for connections
		// The base URL will point to our gateway server, which will handle the details of the connection for us
		[baseURL release];
		baseURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"http://localhost:%i", gatewayPort]];
		
		// Configure gateway to use TLS/SSL if needed
		if([[baseURL scheme] isEqualToString:@"https"])
		{
			[[[NSApp delegate] helperProxy] gatewayWithLocalPort:gatewayPort setIsSecure:YES];
		}
	}
	
	// Configure gateway with new/updated credentials
	[[[NSApp delegate] helperProxy] gatewayWithLocalPort:gatewayPort setUsername:username password:password];
}

/**
 * Configures the player to play the specified track.
 * 
 * If the player is currently playing a movie, the player is stopped, and the movie is released.
 *
 * @param track - Track dictionary from ITunesData.
**/
- (void)setTrack:(ITunesTrack *)track
{
	// Stop and release the current movie if needed
	if(movie != nil)
	{
		// Update status variables
		shouldPlay = NO;
		wasPlaying = NO;
		
		// Get rid of the previous movie
		[movie stop];
		[movie release];
		movie = nil;
		
		// And stop any monitoring of the movie
		[self teardownQTMonitor];
	}
	
	// Save reference to this track
	[currentTrack release];
	currentTrack = [track retain];
	
	// We do NOT initialize the movie here
	// Because doing so would cause the movie to start downloading the song
	// If the user is just clicking next to go through the songs, this may cause excess traffic
	
	// Inform delegate of track change
	if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeTrack:)])
	{
		[delegate iTunesPlayerDidChangeTrack:self];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Player Status Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isPlayable
{
	if(movie)
	{
		return ([[movie attributeForKey:QTMovieLoadStateAttribute] longValue] >= kMovieLoadStatePlayable);
	}
	return NO;
}

/**
 * Returns whether or not the player is currently playing anything.
 * 
 * This method only returns YES if the player is actually in the process of playing.
 * It will return NO if the player is buffering/loading, or still making a connection.
 * So even if you call play, this method may still return NO.
**/
- (BOOL)isPlaying
{
	return (movie != nil) && ([movie rate] != 0);
}

/**
 * Returns YES if you have called play, and have not called pause or stop, and the movie has not failed or finished.
 * Use this method to determine if the player is attempting to play something.
**/
- (BOOL)isPlayingOrBuffering
{
	return shouldPlay;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Player Control Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Plays/Resumes the player.
 * 
 * If the track or playlist has not been set, this method has no effect.
 * If a track or playlist has been set, and a series of play/stop methods have been invoked, the player starts playing
 * where it left off (unpauses).
**/
- (void)play
{
	BOOL didInitNewMovie = NO;
	
	// Initialize the QTMovie if needed
	if((movie == nil) && (currentTrack != nil))
	{
		if([[currentTrack type] isEqualToString:@"File"])
		{
			int trackID = [currentTrack trackID];
			
			NSString *persistentTrackID = [currentTrack persistentID];
			NSString *filetype = [currentTrack pathExtension];
			NSString *filename = [NSString stringWithFormat:@"song.%@", filetype];
			
			NSString *songPath = [NSString stringWithFormat:@"%i/%@/%@", trackID, persistentTrackID, filename];
			NSURL *songURL = [NSURL URLWithString:songPath relativeToURL:baseURL];
			
			// QTMovie wants an absolute URL for some reason (bug...)
			NSURL *absoluteURL = [NSURL URLWithString:[songURL absoluteString]];
			
			//NSLog(@"SongURL: %@", absoluteURL);
			
			movie = [[QTMovie alloc] initWithURL:absoluteURL error:nil];
			
			[movie setVolume:volumePercentage];
			
			didInitNewMovie = YES;
		}
	}
	
	// Don't bother trying to play the movie if there is no movie, or if it's already playing
	if((movie != nil) && ([movie rate] == 0))
	{
		// Try to start playing the song
		// This may or may not work depending on the load state of the movie
		// If we're trying to stream a song for the first time, none of it will be loaded and it won't play yet
		// If we've been streaming the song, it should immediately start playing
		[movie play];
		
		// Is this the first time we've tried to play this song?
		// Remember: This method is also called while loading the song stream over the network or internet
		if(!shouldPlay)
		{
			// Regardless of whether or not the song is actually playing, we want to say that it should be playing
			// That way, if it's not playing, we'll know to immediately start playing it when the load state changes
			shouldPlay = YES;
			
			// If this is the first time we've started loading the movie, notify the delegate
			if(didInitNewMovie)
			{
				if([delegate respondsToSelector:@selector(iTunesPlayerDidStartLoading:)])
				{
					[delegate iTunesPlayerDidStartLoading:self];
				}
			}
			
			// Start monitoring the movie for changes in playback time or load progress
			[self setupQTMonitor];
		}
		
		// If the song actually did start playing, we want to update our variables, and notify the delegate
		if(!wasPlaying)
		{
			if([self isPlaying])
			{
				wasPlaying = YES;
			
				if([delegate respondsToSelector:@selector(iTunesPlayerDidStartPlaying:)])
				{
					[delegate iTunesPlayerDidStartPlaying:self];
				}
			}
			else
			{
				// Waiting for song to load...
			}
		}
		else
		{
			// Already started playing once...
		}
	}
}

/**
 * Pauses the player from playing.
 * If the song is still loading, it will continue loading and the delegate methods will continue to be called.
 * 
 * If the track or playlist has not been set, or the movie is not playing, this method has no effect.
**/
- (void)pause
{
	if(movie != nil)
	{
		// Note: It seems to work a lot better if we stop the movie AFTER we've updated our variables
		// I'm not sure why at this point, but this has been my experience...
		shouldPlay = NO;
		wasPlaying = NO;
		[movie stop];
		
		// Now we want to check to see if the movie is still loading
		// If it is, we want to continue monitoring it so the GUI is properly updated
		
		long loadState = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
		
		if((loadState == kMovieLoadStateComplete) || (loadState == kMovieLoadStateError))
		{
			// The movie has either completed loading, or it stopped loading because of an error
			// Either way, we don't need to continue monitoring it
			[self teardownQTMonitor];
		}
	}
}

/**
 * Stops the song from playing, and stops the song from loading.
 * The currentTrack will be set to nil.
**/
- (void)stop
{
	if(movie)
	{
		shouldPlay = NO;
		wasPlaying = NO;
		[movie stop];
		
		[self teardownQTMonitor];
		
		[movie release];
		movie = nil;
		
		[currentTrack release];
		currentTrack = nil;
		
		// Inform delegate of track change
		if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeTrack:)])
		{
			[delegate iTunesPlayerDidChangeTrack:self];
		}
	}
}

/**
 * Returns the track dictionary of the currently playing song.
**/
- (ITunesTrack *)currentTrack
{
	return currentTrack;
}

/**
 * Returns (as a percentage) the amount of the song that's been loaded so far.
**/
- (float)loadProgress
{
	if(movie)
	{
		// typedef long TimeValue
		TimeValue loadProgress;
		GetMaxLoadedTimeInMovie([movie quickTimeMovie], &loadProgress);
		
		// typedef struct { long long timeValue; long timeScale; long flags; } QTTime
		QTTime qtDuration    = [movie duration];
		long long duration = qtDuration.timeValue;
		
		if(duration > 0)
			return ((float)loadProgress) / ((float)duration);
		else
			return 0;
	}
	else
	{
		return 0;
	}
}

/**
 * This method allows scrubbing of songs by allowing the current time of the track to be changed.
**/
- (void)setPlayProgress:(float)percent
{
	if(movie)
	{
		// Validate percent value
		if(percent < 0) {
			percent = 0;
		}
		else if(percent > 1) {
			percent = 1;
		}
		
		// Silently ignore the request if trying to skip ahead of what's loaded
		if(percent < [self loadProgress])
		{
			QTTime oldTime = [movie currentTime];

			QTTime qtDuration = [movie duration];
			
			long long newTimeValue = (long long)(((float)qtDuration.timeValue) * percent);
			
			QTTime newTime = QTMakeTime(newTimeValue, oldTime.timeScale);
			[movie setCurrentTime:newTime];
			
			if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeLoadOrTime:)])
			{
				[delegate iTunesPlayerDidChangeLoadOrTime:self];
			}
		}
	}
}

/**
 * Returns the current progress (as a percentage complete) of the song that's playing.
 * If no song is playing, this method returns 0.
**/
- (float)playProgress
{
	if(movie)
	{
		QTTime qtCurrentTime = [movie currentTime];
		QTTime qtDuration    = [movie duration];
		
		long long currentTime = qtCurrentTime.timeValue;
		long long duration = qtDuration.timeValue;
		
		if(duration > 0)
			return ((float)currentTime) / ((float)duration);
		else
			return 0;
	}
	else
	{
		return 0;
	}

}

/**
 * Sets the volume of the player.
 * This is the volume of this player, NOT the system volume.
 * 
 * @param percent - Percentage of volume. The valid range is 0.0 to 1.0.
**/
- (void)setVolume:(float)percent
{
	if(percent < 0.0F)
		volumePercentage = 0.0F;
	else if(percent > 1.0F)
		volumePercentage = 1.0F;
	else
		volumePercentage = percent;
	
	[movie setVolume:volumePercentage];
}

- (float)volume
{
	return volumePercentage;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark QT Monitoring:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setupQTMonitor
{
	// Check to see if we already have a timer
	// We might if the song was paused while the song was still loading
	if(!timer)
	{
		// Schedule a timer to check on the movie a few times every second
		// This way we can inform our delegate of changes to the load progress and play progress
		timer = [[NSTimer scheduledTimerWithTimeInterval:0.50
												  target:self
												selector:@selector(checkOnMovie:)
												userInfo:nil
												 repeats:YES] retain];
		
		// Now this is a little bit tricky, because the timer just retained us.
		// And since we reatin our timer, we now have a circular reference.
		// Often this isn't much of a problem...
		// But if our delegate releases us while a movie is still playing or loading, we won't be deallocated.
		// The timer will still fire, and a the application will crash when we attempt to contact the delegate!
		// To solve this dilemma, we handle the problem internally, and correct the retain count.
		[self release];
	}
}

- (void)teardownQTMonitor
{
	// Check to see if we even have a timer setup
	if(timer)
	{
		// We must first retain ourself
		// We do this because we released ourself when we created the timer in order to keep a proper retain count.
		[self retain];
		
		// And now we can invalidate the timer
		[timer invalidate];
		[timer release];
		timer = nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notification Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when a song has finished playing.
 * However, this method may also be called if we try to play a song that's not loaded yet.
 * 
 * This is used to notify the delegate that a song is no longer playing.
**/
- (void)movieFinished:(NSNotification *)notification
{
	// First make sure that this notification is for our movie.
	// There may be multiple ITunesPlayer instances. Such would be the case if browsing multiple libraries.
	if([notification object] == movie)
	{
		// We check to see if the movie was previously playing, because this method is immediately called if
		// we try to play a song that needs to be streamed and isn't loaded yet.
		if(wasPlaying)
		{
			// Update our variables
			shouldPlay = NO;
			wasPlaying = NO;
			
			// We can stop monitoring our movie now
			[self teardownQTMonitor];
			
			// Notify the delegate (one last time) that the play time has changed
			if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeLoadOrTime:)])
			{
				[delegate iTunesPlayerDidChangeLoadOrTime:self];
			}
			
			// Notify the delegate that the movie has finished
			if([delegate respondsToSelector:@selector(iTunesPlayerDidFinishPlaying:)])
			{
				[delegate iTunesPlayerDidFinishPlaying:self];
			}
		}
	}
}

/**
 * This method is called when the load state of a movie changes.
 * It will be called multiple times as the movie continues to load.
 * 
 * We use this method to immediately start playing the movie as soon as it's ready.
 * 
 * The possible load states during asynchronous movie loading are these:
 *
 * kMovieLoadStateLoading       — QuickTime still instantiating the movie.
 * kMovieLoadStatePlayable      — movie fully formed and can be played; media data still downloading.
 * kMovieLoadStatePlaythroughOK — media data still downloading, but all data is expected to arrive before it is needed.
 * kMovieLoadStateComplete      — all media data is available.
 * kMovieLoadStateError         — movie loading failed; a movie may have been created, but it is not playable.
**/
- (void)movieLoadStateDidChange:(NSNotification *)notification
{
	// First make sure that this notification is for our movie.
	// There may be multiple ITunesPlayer instances. Such would be the case if browsing multiple libraries.
	if([notification object] == movie)
	{
		long loadState = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
		
		if(shouldPlay && ![self isPlaying])
		{
			// Check to see if we can start playing the song yet
			
			if(loadState >= kMovieLoadStatePlaythroughOK)
			{
				[self play];
			}
		}
		else if(!shouldPlay)
		{
			// Check to see if the movie is still loading
			// If it's not we can tear down the timer/monitor we have setup
			
			if((loadState == kMovieLoadStateComplete) || (loadState == kMovieLoadStateError))
			{
				// The movie has either completed loading, or it stopped loading because of an error
				// Either way, we don't need to continue monitoring it
				[self teardownQTMonitor];
				
				// Notify the delegate (one last time) that the load percent has changed
				if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeLoadOrTime:)])
				{
					[delegate iTunesPlayerDidChangeLoadOrTime:self];
				}
			}
		}
		
		if((loadState == kMovieLoadStateComplete) || (loadState == kMovieLoadStateError))
		{
			// Notify the delegate that the loading is complete
			if([delegate respondsToSelector:@selector(iTunesPlayerDidFinishLoading:)])
			{
				[delegate iTunesPlayerDidFinishLoading:self];
			}
		}
	}
}

- (void)checkOnMovie:(NSTimer *)aTimer
{
	// Invoke delegate method if it implements the proper method
	if([delegate respondsToSelector:@selector(iTunesPlayerDidChangeLoadOrTime:)])
	{
		[delegate iTunesPlayerDidChangeLoadOrTime:self];
	}
}

@end
