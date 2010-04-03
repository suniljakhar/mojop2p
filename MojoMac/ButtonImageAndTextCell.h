#import <Cocoa/Cocoa.h>
#import "DDButtonCell.h"


@interface ButtonImageAndTextCell : NSTextFieldCell <DDButtonCell>
{
  @private
	NSButtonCell *buttonCell;
	NSImage *image;
}

- (NSImage *)image;
- (void)setImage:(NSImage *)image;

@end
