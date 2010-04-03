#import "SliderView.h"

@implementation SliderView

- (id)initWithFrame:(NSRect)frameRect
{
	if((self = [super initWithFrame:frameRect]))
	{
		sliderLeft   = [[NSImage imageNamed:@"sliderLeft.png"] retain];
		sliderMiddle = [[NSImage imageNamed:@"sliderMiddle.png"] retain];
		sliderRight  = [[NSImage imageNamed:@"sliderRight.png"] retain];
		sliderKnob   = [[NSImage imageNamed:@"sliderKnob.png"] retain];
		
		sliderLeftSize   = [sliderLeft size];
		sliderMiddleSize = [sliderMiddle size];
		sliderRightSize  = [sliderRight size];
		sliderKnobSize   = [sliderKnob size];
		
		minValue = 0.0;
		maxValue = 1.0;
		currentValue = 1.0;
	}
	return self;
}

- (void)dealloc
{
	[sliderLeft release];
	[sliderMiddle release];
	[sliderRight release];
	[sliderKnob release];
	[super dealloc];
}

- (id)target
{
	return target;
}

- (void)setTarget:(id)anObject
{
	target = anObject;
}

- (SEL)action
{
	return action;
}

- (void)setAction:(SEL)aSelector
{
	action = aSelector;
}

- (double)minValue
{
	return minValue;
}

- (void)setMinValue:(double)newMinValue
{
	if(newMinValue < maxValue)
	{
		minValue = newMinValue;
		[self setNeedsDisplay:YES];
	}
}

- (double)maxValue
{
	return maxValue;
}

- (void)setMaxValue:(double)newMaxValue
{
	if(newMaxValue > minValue)
	{
		maxValue = newMaxValue;
		[self setNeedsDisplay:YES];
	}
}

- (double)doubleValue
{
	return currentValue;
}

- (void)setDoubleValue:(double)aDouble
{
	currentValue = aDouble;
	
	if(currentValue < minValue) {
		currentValue = minValue;
	}
	else if(currentValue > maxValue) {
		currentValue = maxValue;
	}
	
	[self setNeedsDisplay:YES];
}

- (float)floatValue
{
	return (float)currentValue;
}

- (void)setFloatValue:(float)aFloat
{
	currentValue = (double)aFloat;
	
	if(currentValue < minValue) {
		currentValue = minValue;
	}
	else if(currentValue > maxValue) {
		currentValue = maxValue;
	}
	
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
	// Draw slider background
	
	[sliderLeft drawAtPoint:NSMakePoint(0,3)
				   fromRect:NSZeroRect
				  operation:NSCompositeSourceOver
				   fraction:1];
	
	NSRect sliderMiddleRect;
	sliderMiddleRect.origin.x = sliderLeftSize.width;
	sliderMiddleRect.origin.y = 3;
	sliderMiddleRect.size.width = rect.size.width - sliderLeftSize.width - sliderRightSize.width;
	sliderMiddleRect.size.height = 6;
	
	[sliderMiddle drawInRect:sliderMiddleRect
					fromRect:NSZeroRect
				   operation:NSCompositeSourceOver
					fraction:1];
	
	[sliderRight drawAtPoint:NSMakePoint(rect.size.width - [sliderRight size].width, 3)
					fromRect:NSZeroRect
				   operation:NSCompositeSourceOver
					fraction:1];
	
	// Draw slider knob
	
	float percent = (float)((currentValue - minValue) / (maxValue - minValue));
	
	NSPoint sliderKnobPoint;
	sliderKnobPoint.x = (rect.size.width - sliderKnobSize.width) * percent;
	sliderKnobPoint.y = 0;
		
	[sliderKnob drawAtPoint:sliderKnobPoint
				   fromRect:NSZeroRect
				  operation:NSCompositeSourceOver
				   fraction:1];
}

- (void)mouseDown:(NSEvent *)theEvent
{
	// Get the location within the view of where the user clicked
	NSPoint locationInWindow = [theEvent locationInWindow];
	NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];
	
	// Here is the tricky part:
	// A click within the slider should move the center of the knob to the position of the mouse pointer
	// Thus in our calculations we need to consider the width of the knob so it's positioned appropriately
	
	NSRect offsetTrackRect = NSInsetRect([self bounds], (sliderKnobSize.width / 2.0F), 0.0F);
	
	float percent = (locationInView.x - offsetTrackRect.origin.x) / offsetTrackRect.size.width;
	
	if(percent < 0.0F) {
		percent = 0.0F;
	}
	else if(percent > 1.0F) {
		percent = 1.0F;
	}
	
	currentValue = minValue + ((maxValue - minValue) * percent);
	
	// We need to redraw the slider display
	[self setNeedsDisplay:YES];
	
	// Also, we need to redraw the background LCD display
	[[self superview] setNeedsDisplay:YES];
	
	// Fire event
	[target performSelector:action withObject:self];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	[self mouseDown:theEvent];
}

@end
