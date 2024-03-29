#import "ImageAndTextCell.h"

@implementation ImageAndTextCell

- (void)dealloc
{
    [image release];
    image = nil;
    [super dealloc];
}

- copyWithZone:(NSZone *)zone
{
	ImageAndTextCell *cell = (ImageAndTextCell *)[super copyWithZone:zone];
    cell->image = [image retain];
    return cell;
}

- (void)setImage:(NSImage *)anImage
{
	if(anImage != image)
	{
		[image release];
		image = [anImage retain];
	}
}

- (NSImage *)image
{
	return image;
}

- (NSRect)imageFrameForCellFrame:(NSRect)cellFrame
{
	if(image != nil)
	{
		NSRect imageFrame;
		imageFrame.size = [image size];
		imageFrame.origin = cellFrame.origin;
		imageFrame.origin.x += 3;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		return imageFrame;
	}
	else
		return NSZeroRect;
}

- (void)editWithFrame:(NSRect)aRect
			   inView:(NSView *)controlView
			   editor:(NSText *)textObj
			 delegate:(id)anObject
				event:(NSEvent *)theEvent
{
    NSRect textFrame, imageFrame;
    NSDivideRect(aRect, &imageFrame, &textFrame, 6 + [image size].width, NSMinXEdge);
    [super editWithFrame:textFrame inView:controlView editor:textObj delegate:anObject event:theEvent];
}

- (void)selectWithFrame:(NSRect)aRect
				 inView:(NSView *)controlView
				 editor:(NSText *)textObj
			   delegate:(id)anObject
				  start:(int)selStart
				 length:(int)selLength
{
    NSRect textFrame, imageFrame;
    NSDivideRect(aRect, &imageFrame, &textFrame, 6 + [image size].width, NSMinXEdge);
    [super selectWithFrame:textFrame inView: controlView editor:textObj delegate:anObject start:selStart length:selLength];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if(image != nil)
	{
		NSSize imageSize;
		NSRect imageFrame;
		
		imageSize = [image size];
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 6 + imageSize.width, NSMinXEdge);
		if([self drawsBackground])
		{
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}
		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		
		if([controlView isFlipped])
			imageFrame.origin.y += ceilf((cellFrame.size.height + imageFrame.size.height) / 2.0F);
		else
			imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		[image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver];
	}
	[super drawWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSSize textContentSize = [super cellSize];
	cellFrame.origin.y += (cellFrame.size.height - textContentSize.height) / 2.0F;
	cellFrame.size.height = textContentSize.height;
	
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];
	cellSize.width += (image ? [image size].width : 0) + 6;
	return cellSize;
}

@end

