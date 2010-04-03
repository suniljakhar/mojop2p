#import "ButtonAndTextCell.h"
#import "DDTableView.h"


@implementation ButtonAndTextCell

- (void)dealloc
{
	[leftImage release];            leftImage = nil;
	[rightImage release];           rightImage = nil;
	[alternateLeftImage release];   alternateLeftImage = nil;
	[alternateRightImage release];  alternateRightImage = nil;
	
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	ButtonAndTextCell *cell = (ButtonAndTextCell *)[super copyWithZone:zone];
	cell->leftImage = [leftImage retain];
	cell->rightImage = [rightImage retain];
	cell->alternateLeftImage = [alternateLeftImage retain];
	cell->alternateRightImage = [alternateRightImage retain];
    return cell;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Left:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setLeftImage:(NSImage *)anImage
{
	if(anImage != leftImage)
	{
		[leftImage release];
		leftImage = [anImage retain];
	}
}

- (NSImage *)leftImage
{
	return leftImage;
}

- (void)setAlternateLeftImage:(NSImage *)anImage
{
	if(anImage != alternateLeftImage)
	{
		[alternateLeftImage release];
		alternateLeftImage = [anImage retain];
	}
}

- (NSImage *)alternateLeftImage
{
	return alternateLeftImage;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Right:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setRightImage:(NSImage *)anImage
{
	if(anImage != rightImage)
	{
		[rightImage release];
		rightImage = [anImage retain];
	}
}

- (NSImage *)rightImage
{
	return rightImage;
}

- (void)setAlternateRightImage:(NSImage *)anImage
{
	if(anImage != alternateRightImage)
	{
		[alternateRightImage release];
		alternateRightImage = [anImage retain];
	}
}

- (NSImage *)alternateRightImage
{
	return alternateRightImage;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Functionality:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	DDTableView *tableView = (DDTableView *)controlView;
	
	if(leftImage)
	{
		NSSize imageSize = [leftImage size];
		NSRect imageFrame;
		
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 6 + imageSize.width, NSMinXEdge);
		
		if([self drawsBackground])
		{
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}
		
		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		NSImage *currentLeftImage;
		if(NSPointInRect([tableView clickedPointInTable], imageFrame))
			currentLeftImage = alternateLeftImage;
		else
			currentLeftImage = leftImage;
		
		[currentLeftImage setFlipped:[controlView isFlipped]];
		[currentLeftImage drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
	}
	
	if(rightImage)
	{
		NSSize imageSize = [rightImage size];
		NSRect imageFrame;
		
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 6 + imageSize.width, NSMaxXEdge);
		
		if([self drawsBackground])
		{
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}
		
		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		NSImage *currentRightImage;
		if(NSPointInRect([tableView clickedPointInTable], imageFrame))
			currentRightImage = alternateRightImage;
		else
			currentRightImage = rightImage;
		
		[currentRightImage setFlipped:[controlView isFlipped]];
		[currentRightImage drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
	}
	
	[super drawWithFrame:cellFrame inView:controlView];
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];
	if(leftImage)
	{
		cellSize.width += [leftImage size].width + 6;
	}
	if(rightImage)
	{
		cellSize.width += [rightImage size].width + 6;
	}
	return cellSize;
}

- (int)numberOfButtons
{
	if(leftImage)
	{
		if(rightImage)
			return 2;
		else
			return 1;
	}
	else if(rightImage)
	{
		// We actually have to return 2 here, because the buttons are checked (on mouseDown) in order
		return 2;
	}
	
	return 0;
}

- (NSRect)button:(int)index rectForBounds:(NSRect)theRect
{
	if((index == 0) && (leftImage != nil))
	{
		NSRect imageRect;
		imageRect.size = [leftImage size];
		imageRect.origin = theRect.origin;
		imageRect.origin.x += 3;
		imageRect.origin.y += ceilf((theRect.size.height - imageRect.size.height) / 2.0F);
		return imageRect;
	}
	else if((index == 1) && (rightImage != nil))
	{
		NSRect imageRect;
		imageRect.size = [rightImage size];
		imageRect.origin.x = theRect.origin.x + theRect.size.width - imageRect.size.width;
		imageRect.origin.y = theRect.origin.y;
		imageRect.origin.x += 3;
		imageRect.origin.y += ceilf((theRect.size.height - imageRect.size.height) / 2.0F);
		return imageRect;
	}
	
	return NSZeroRect;
}

@end
