#import "SongProgressView.h"
#import "ITunesPlayer.h"


@implementation SongProgressView

- (id)initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
	{
		borderColor = [[NSColor colorWithDeviceRed:( 96.0F / 255.0F)
											 green:( 96.0F / 255.0F)
											  blue:( 96.0F / 255.0F) alpha:1.0F] retain];
		
		playColor   = [[NSColor colorWithDeviceRed:(255.0F / 255.0F)
											 green:(255.0F / 255.0F)
											  blue:(255.0F / 255.0F) alpha:1.0F] retain];
		
		loadColor   = [[NSColor colorWithDeviceRed:( 45.0F / 255.0F)
											 green:( 45.0F / 255.0F)
											  blue:( 45.0F / 255.0F) alpha:1.0F] retain];
	}
	return self;
}

- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
	[borderColor release];
	[playColor release];
	[loadColor release];
	[super dealloc];
}

- (void)setITunesPlayer:(ITunesPlayer *)iTunesPlayer
{
	itp = iTunesPlayer;
}

- (void)drawRect:(NSRect)rect
{
	// Draw the square black outline
	[borderColor set];
	NSFrameRect(rect);
	
	// Draw the load and progress indicator
	NSRect insetRect = NSInsetRect(rect, 2, 2);
	
	if(itp)
	{
		NSRect loadRect = insetRect;
		loadRect.size.width = insetRect.size.width * [itp loadProgress];
		
		[loadColor set];
		NSRectFill(loadRect);
		
		NSRect progressRect = insetRect;
		progressRect.size.width = insetRect.size.width * [itp playProgress];
		
		[playColor set];
		NSRectFill(progressRect);
	}
}

- (void)mouseDown:(NSEvent *)theEvent
{
	// Get the location within the button that the user clicked
	NSPoint locationInWindow = [theEvent locationInWindow];
	NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];
	
	if(itp)
	{
		// Calculate our progress rect
		NSRect progressRect = NSInsetRect([self bounds], 2, 2);
		
		// Calculate percent
		float percent = locationInView.x / progressRect.size.width;
		
		if(percent < 0) {
			percent = 0;
		}
		else if(percent > 1) {
			percent = 1;
		}
		
		[itp setPlayProgress:percent];
	}
	
	// We need to redraw the progress display
	[self setNeedsDisplay:YES];
	
	// Also, we need to redraw the background LCD display
	[[self superview] setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	[self mouseDown:theEvent];
}

@end
