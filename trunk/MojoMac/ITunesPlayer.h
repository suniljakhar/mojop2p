#import <Foundation/Foundation.h>
#import <QTKit/QTKit.h>
#import <QuickTime/QuickTime.h>

@class ITunesTrack;


@interface ITunesPlayer : NSObject
{
	// Stored base URL
	NSURL *baseURL;
	
	// The current movie this object is playing
	QTMovie *movie;
	
	// Should Play status
	BOOL shouldPlay;
	BOOL wasPlaying;
	
	// Volume percentage at which to play movies
	float volumePercentage;
	
	// Current track that is playing
	ITunesTrack *currentTrack;
	
	// Delegate
	id delegate;
	
	// Timer to monitor load state and current time
	NSTimer *timer;
	
	// Gateway setup
	BOOL isOurGateway;
	UInt16 gatewayPort;
}

- (id)initWithBaseURL:(NSURL *)baseURL isGateway:(BOOL)flag;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (void)setUsername:(NSString *)username password:(NSString *)password;

- (void)setTrack:(ITunesTrack *)track;

- (BOOL)isPlayable;
- (BOOL)isPlaying;
- (BOOL)isPlayingOrBuffering;

- (void)play;
- (void)pause;
- (void)stop;

- (ITunesTrack *)currentTrack;

- (float)loadProgress;

- (void)setPlayProgress:(float)percent;
- (float)playProgress;

- (void)setVolume:(float)volume;
- (float)volume;

@end

// DELEGATE METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (ITunesPlayerDelegate)

/**
 * Called when the song is changed.
**/
- (void)iTunesPlayerDidChangeTrack:(id)sender;

/**
 * Called when the player has started buffering/loading a song.
**/
- (void)iTunesPlayerDidStartLoading:(id)sender;

/**
 * Called when the song has started playing.
**/
- (void)iTunesPlayerDidStartPlaying:(id)sender;

/**
 * Called consistently (every 0.5 seconds) while the song is either playing or loading.
**/
- (void)iTunesPlayerDidChangeLoadOrTime:(id)sender;

/**
 * Called when the song has finished loading.
**/
- (void)iTunesPlayerDidFinishLoading:(id)sender;

/**
 * Called when the song has finished playing.
**/
- (void)iTunesPlayerDidFinishPlaying:(id)sender;

@end
