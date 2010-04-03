/* SongProgressView */

#import <Cocoa/Cocoa.h>

@class ITunesPlayer;

@interface SongProgressView : NSView
{
	NSColor *borderColor;
	NSColor *playColor;
	NSColor *loadColor;
	
	ITunesPlayer *itp;
}
- (void)setITunesPlayer:(ITunesPlayer *)iTunesPlayer;
@end
