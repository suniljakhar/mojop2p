/* SliderView */

#import <Cocoa/Cocoa.h>

@interface SliderView : NSView
{
	NSImage *sliderLeft;
	NSImage *sliderMiddle;
	NSImage *sliderRight;
	NSImage *sliderKnob;
	
	NSSize sliderLeftSize;
	NSSize sliderMiddleSize;
	NSSize sliderRightSize;
	NSSize sliderKnobSize;
	
	id target;
	SEL action;
	
	double minValue;
	double maxValue;
	double currentValue;
}

- (id)target;
- (void)setTarget:(id)anObject;

- (SEL)action;
- (void)setAction:(SEL)aSelector;

- (double)minValue;
- (void)setMinValue:(double)minValue;

- (double)maxValue;
- (void)setMaxValue:(double)maxValue;

- (double)doubleValue;
- (void)setDoubleValue:(double)aDouble;

- (float)floatValue;
- (void)setFloatValue:(float)aFloat;

@end
