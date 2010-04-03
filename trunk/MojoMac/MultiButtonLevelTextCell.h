#import <Cocoa/Cocoa.h>
#import "DDButtonCell.h"

@interface MultiButtonLevelTextCell : NSLevelIndicatorCell <DDButtonCell>
{
  @private
	NSImage	*image1;
	NSImage *image2;
	NSImage *alternateImage1;
	NSImage *alternateImage2;
	NSString *string;
}

- (void)setImage1:(NSImage *)anImage;
- (NSImage *)image1;

- (void)setAlternateImage1:(NSImage *)anImage;
- (NSImage *)alternateImage1;

- (void)setImage2:(NSImage *)anImage;
- (NSImage *)image2;

- (void)setAlternateImage2:(NSImage *)anImage;
- (NSImage *)alternateImage2;

- (void)setStringValue:(NSString *)aString;
- (NSString *)stringValue;

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (NSSize)cellSize;

@end
