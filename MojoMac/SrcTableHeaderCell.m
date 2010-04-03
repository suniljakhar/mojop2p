//  Originally Created by Matt Gemmell on Thu Feb 05 2004.

#import "SrcTableHeaderCell.h"


@implementation SrcTableHeaderCell


- (id)initTextCell:(NSString *)text
{
	if((self = [super initTextCell:text]))
	{
		metalBg = [[NSImage imageNamed:@"metalColumnHeader.png"] retain];
		[metalBg setFlipped:YES];
		
		if(text == nil)
		{
			[self setTitle:@""];
		}
		
		attrs = [[NSMutableDictionary dictionaryWithDictionary:
									[[self attributedStringValue] attributesAtIndex:0
																     effectiveRange:NULL]] mutableCopy];
	}
    return self;
}


- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
    [metalBg release];
    [attrs release];
    [super dealloc];
}

- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView
{
	// Draw metalBg image, covering the entire frame
	[metalBg drawInRect:inFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
    
	// Draw white text centered, but offset down-left.
    float offset = 0.5F;
    [attrs setValue:[NSColor colorWithCalibratedWhite:1.0F alpha:0.7F] forKey:@"NSColor"];
    
    NSRect centeredRect = inFrame;
    centeredRect.size = [[self stringValue] sizeWithAttributes:attrs];
    centeredRect.origin.x = ((inFrame.size.width - centeredRect.size.width) / 2.0F) - offset;
	centeredRect.origin.y = ((inFrame.size.height - centeredRect.size.height) / 2.0F) + offset;
    [[self stringValue] drawInRect:centeredRect withAttributes:attrs];
	
	// Draw black text centered
	[attrs setValue:[NSColor blackColor] forKey:@"NSColor"];
	centeredRect.origin.x += offset;
	centeredRect.origin.y -= offset;
	[[self stringValue] drawInRect:centeredRect withAttributes:attrs];
}

- (id)copyWithZone:(NSZone *)zone
{
	id newCopy = [super copyWithZone:zone];
	[metalBg retain];
	[attrs retain];
	return newCopy;
}

@end
