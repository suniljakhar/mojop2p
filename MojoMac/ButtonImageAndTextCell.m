#import "ButtonImageAndTextCell.h"
#import "DDOutlineView.h"


@implementation ButtonImageAndTextCell

- (void)setupButtonCell
{
	[buttonCell release];
	
	buttonCell = [[NSButtonCell alloc] init];
	[buttonCell setButtonType:NSSwitchButton];
	[buttonCell setAllowsMixedState:YES];
	[buttonCell setTitle:nil];
}

- (id)initTextCell:(NSString *)aString
{
	if((self = [super init]))
	{
		[self setupButtonCell];
		[self setAllowsMixedState:YES];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if((self = [super initWithCoder:aDecoder]))
	{
		[self setupButtonCell];
		[self setAllowsMixedState:YES];
	}
	return self;
}

- (void)dealloc
{
	[buttonCell release];  buttonCell = nil;
	[image release];       image = nil;
		
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	ButtonImageAndTextCell *cell = (ButtonImageAndTextCell *)[super copyWithZone:zone];
    cell->buttonCell = [buttonCell retain];
	cell->image = [image retain];
    return cell;
}

- (NSImage *)image
{
	return image;
}

- (void)setImage:(NSImage *)newImage
{
	if(image != newImage)
	{
		[image release];
		image = [newImage copy];
	}
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	DDOutlineView *outlineView = (DDOutlineView *)controlView;
	BOOL isEnabled = [outlineView isEnabled];
	
	NSSize buttonSize = [buttonCell cellSize];
	
	NSRect buttonFrame;
	NSDivideRect(cellFrame, &buttonFrame, &cellFrame, buttonSize.width, NSMinXEdge);
	
	BOOL isHighlighted = NSPointInRect([outlineView clickedPointInTable], buttonFrame);
	
	[buttonCell setState:[self state]];
	[buttonCell setEnabled:isEnabled];
	[buttonCell setHighlighted:isHighlighted];
	[buttonCell drawWithFrame:buttonFrame inView:controlView];
	
	if(image)
	{
		NSSize imageSize = [image size];
		
		NSRect imageFrame;
		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 3 + imageSize.width, NSMinXEdge);
		
		if([self drawsBackground])
		{
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}
		
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceilf((cellFrame.size.height - imageFrame.size.height) / 2.0F);
		
		[image setFlipped:[controlView isFlipped]];
		[image drawInRect:imageFrame fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0F];
	}
	if(isEnabled)
		[super setTextColor:[NSColor blackColor]];
	else
		[super setTextColor:[NSColor grayColor]];
	
	[super drawWithFrame:cellFrame inView:controlView];
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];
	
	cellSize.width += [buttonCell cellSize].width;
	
	if(image)
	{
		cellSize.width += [image size].width + 3;
	}
	
	return cellSize;
}

- (int)numberOfButtons
{
	return 1;
}

- (NSRect)button:(int)index rectForBounds:(NSRect)cellFrame
{
	NSSize buttonSize = [buttonCell cellSize];
	
	NSRect buttonFrame;
	buttonFrame.origin.x = cellFrame.origin.x;
	buttonFrame.origin.y = cellFrame.origin.y;
	
	buttonFrame.origin.y += ceilf((cellFrame.size.height - buttonSize.height) / 2.0F);
	
	buttonFrame.size.width = buttonSize.width;
	buttonFrame.size.height = buttonSize.height;
	
	return buttonFrame;
}

@end
