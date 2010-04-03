#import "MultiButtonLevelTextCell.h"
#import "DDTableView.h"


@implementation MultiButtonLevelTextCell

static NSDictionary *normalTextAttributes;
static NSDictionary *highlightedTextAttributes;

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		
		// Setup paragraph style (Alignment, line breaking, etc)
		NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
		
		// Setup normal attributes
		NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
		
		NSMutableDictionary *normalAttr = [NSMutableDictionary dictionaryWithCapacity:1];
		[normalAttr setObject:font forKey:NSFontAttributeName];
		
		normalTextAttributes = [normalAttr copy];
		
		// Setup highlighted attributes
		NSColor *color = [NSColor whiteColor];
		
		NSMutableDictionary *highlightedAttr = [NSMutableDictionary dictionaryWithCapacity:1];
		[highlightedAttr setObject:font forKey:NSFontAttributeName];
		[highlightedAttr setObject:color forKey:NSForegroundColorAttributeName];
		
		highlightedTextAttributes = [highlightedAttr copy];
	}
}

- (void)dealloc
{
	[image1 release];                 image1 = nil;
	[image2 release];                 image2 = nil;
	[alternateImage1 release];        alternateImage1 = nil;
	[alternateImage2 release];        alternateImage2 = nil;
	[string release];                 string = nil;
	
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	MultiButtonLevelTextCell *cell = (MultiButtonLevelTextCell *)[super copyWithZone:zone];
    cell->image1 = [image1 retain];
	cell->image2 = [image2 retain];
	cell->alternateImage1 = [alternateImage1 retain];
	cell->alternateImage2 = [alternateImage2 retain];
	cell->string = [string retain];
    return cell;
}

- (void)setImage1:(NSImage *)anImage
{
	if(anImage != image1)
	{
		[image1 release];
		image1 = [anImage retain];
	}
}
- (NSImage *)image1
{
	return image1;
}

- (void)setAlternateImage1:(NSImage *)anImage
{
	if(anImage != alternateImage1)
	{
		[alternateImage1 release];
		alternateImage1 = [anImage retain];
	}
}
- (NSImage *)alternateImage1
{
	return alternateImage1;
}

- (void)setImage2:(NSImage *)anImage
{
	if(anImage != image2)
	{
		[image2 release];
		image2 = [anImage retain];
	}
}
- (NSImage *)image2
{
	return image2;
}

- (void)setAlternateImage2:(NSImage *)anImage
{
	if(anImage != alternateImage2)
	{
		[alternateImage2 release];
		alternateImage2 = [anImage retain];
	}
}
- (NSImage *)alternateImage2
{
	return alternateImage2;
}

- (void)setStringValue:(NSString *)aString
{
	if(string != aString)
	{
		[string release];
		string = [aString retain];
	}
}

- (NSString *)stringValue
{
	return string;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	DDTableView *tableView = (DDTableView *)controlView;
	
	if(image1)
	{
		NSSize imageSize = [image1 size];
		NSRect imageFrame;
		
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, imageSize.width + 6, NSMinXEdge);
		
		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		NSImage *currentImage;
		if(NSPointInRect([tableView clickedPointInTable], imageFrame))
			currentImage = alternateImage1;
		else
			currentImage = image1;
		
		[currentImage setFlipped:[controlView isFlipped]];
		[currentImage drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
	}
	
	if(image2)
	{
		NSSize imageSize = [image2 size];
		NSRect imageFrame;
		
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, imageSize.width + 6, NSMinXEdge);
		
		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		NSImage *currentImage;
		if(NSPointInRect([tableView clickedPointInTable], imageFrame))
			currentImage = alternateImage2;
		else
			currentImage = image2;
		
		[currentImage setFlipped:[controlView isFlipped]];
		[currentImage drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
	}
	
	if((string != nil) && ([self doubleValue] == [self minValue]))
	{
		if([self isHighlighted])
		{
			NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
			
			if([highlightColor isEqual:[NSColor alternateSelectedControlColor]])
				[string drawInRect:cellFrame withAttributes:highlightedTextAttributes];
			else
				[string drawInRect:cellFrame withAttributes:normalTextAttributes];
		}
		else
		{
			[string drawInRect:cellFrame withAttributes:normalTextAttributes];
		}
	}
	else
	{
		// We shrink the height of the cell frame, or else the progress bar is too big
		cellFrame.size.height -= 4;
		cellFrame.origin.y += 2;
		
		// We also shrink the width of the cell frame a bit because it looks better
		cellFrame.size.width -= 3;
		
		[super drawWithFrame:cellFrame inView:controlView];
	}
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];
	if(image1 != nil)
	{
		cellSize.width += [image1 size].width + 6;
	}
	if(image2 != nil)
	{
		cellSize.width += [image2 size].width + 6;
	}
	return cellSize;
}

- (int)numberOfButtons
{
	if(image1)
	{
		if(image2)
			return 2;
		else
			return 1;
	}
	else if(image2)
	{
		return 1;
	}
	
	return 0;
}

- (NSRect)button:(int)index rectForBounds:(NSRect)theRect
{
	if((index == 0) && (image1 != nil))
	{
		NSRect imageRect1;
		imageRect1.size = [image1 size];
		imageRect1.origin = theRect.origin;
		imageRect1.origin.x += 3;
		imageRect1.origin.y += ceilf((theRect.size.height - imageRect1.size.height) / 2.0F);
		return imageRect1;
	}
	else if((index == 1) && (image2 != nil))
	{
		NSRect imageRect2;
		imageRect2.size = [image2 size];
		imageRect2.origin = theRect.origin;
		if(image1)
		{
			imageRect2.origin.x += 6;
			imageRect2.origin.x += [image1 size].width;
		}
		imageRect2.origin.x += 3;
		imageRect2.origin.y += ceilf((theRect.size.height - imageRect2.size.height) / 2.0F);
		
		return imageRect2;
	}
	
	return NSZeroRect;
}

@end
