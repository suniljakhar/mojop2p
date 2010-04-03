#import <Cocoa/Cocoa.h>
#import "DDButtonCell.h"

@interface ButtonAndTextCell : NSTextFieldCell <DDButtonCell>
{
  @private
	NSImage	*leftImage;
	NSImage *rightImage;
	NSImage *alternateLeftImage;
	NSImage *alternateRightImage;
}

- (void)setLeftImage:(NSImage *)anImage;
- (NSImage *)leftImage;

- (void)setAlternateLeftImage:(NSImage *)anImage;
- (NSImage *)alternateLeftImage;

- (void)setRightImage:(NSImage *)anImage;
- (NSImage *)rightImage;

- (void)setAlternateRightImage:(NSImage *)anImage;
- (NSImage *)alternateRightImage;

- (NSSize)cellSize;

@end
