#import "DDSplitView.h"

@interface DDSplitViewAnimation : NSObject
{
	CGFloat initialPosition;
	CGFloat finalPosition;
	CGFloat positionIterationChange;
	
	NSInteger dividerIndex;
	
	NSTimeInterval duration;
	NSTimeInterval iteration;
	
	int totalIterations;
	int currentIteration;
	
	NSView *viewToCollapse;
	NSRect collapsedFrame;
}

- (id)initWithInitialPosition:(CGFloat)ip
				finalPosition:(CGFloat)fp
				 dividerIndex:(NSInteger)di
					 duration:(NSTimeInterval)d;

- (id)initWithInitialPosition:(CGFloat)ip
				finalPosition:(CGFloat)fp
				 dividerIndex:(NSInteger)di
					 duration:(NSTimeInterval)d
                      subview:(NSView *)subview;

- (CGFloat)initialPosition;
- (CGFloat)finalPosition;

- (NSInteger)dividerIndex;

- (NSTimeInterval)duration;
- (NSTimeInterval)iteration;

- (int)totalIterations;
- (int)currentIteration;

- (CGFloat)calculateNewPosition;

- (BOOL)isDone;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation DDSplitView

- (void)dealloc
{
	[animationTimer invalidate];
	[animationTimer release];
	[super dealloc];
}

- (CGFloat)positionOfDividerAtIndex:(NSInteger)dividerIndex
{
	if(dividerIndex > [[self subviews] count])
	{
		// Divider does not exist!
		return 0;
	}
	
	NSView *subview = (NSView *)[[self subviews] objectAtIndex:dividerIndex];
	NSRect frame = [subview frame];
	
	if([self isVertical])
	{
		return frame.origin.x + frame.size.width;
	}
	else
	{
		return frame.origin.y + frame.size.height;
	}
}

/**
 * Private Method - Used to animate the collapse of a subview.
**/
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex
                                 withAnimationDuration:(NSTimeInterval)duration
                                      collapsedSubview:(NSView *)subview
{
	if(animationTimer)
	{
		// We are currently in the middle of an animation
		// Immediately set the position of the splitview to it's final position, and then stop the timer
		
		DDSplitViewAnimation *sva = (DDSplitViewAnimation *)[animationTimer userInfo];
		[self setPosition:[sva finalPosition] ofDividerAtIndex:[sva dividerIndex]];
		
		[animationTimer invalidate];
		[animationTimer release];
		animationTimer = nil;
	}
	
	CGFloat initialPosition = [self positionOfDividerAtIndex:dividerIndex];
	
	DDSplitViewAnimation *sva = [[DDSplitViewAnimation alloc] initWithInitialPosition:initialPosition
																		finalPosition:position
																		 dividerIndex:dividerIndex
																			 duration:duration
																			  subview:subview];
	
	animationTimer = [[NSTimer scheduledTimerWithTimeInterval:[sva iteration]
													   target:self
													 selector:@selector(updatePosition:)
													 userInfo:sva
													  repeats:YES] retain];
	
	[sva release];
}

/**
 * Public Method - Used to animate any divider move.
**/
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex
                                 withAnimationDuration:(NSTimeInterval)duration
{
	if(animationTimer)
	{
		// We are currently in the middle of an animation
		// Immediately set the position of the splitview to it's final position, and then stop the timer
		
		DDSplitViewAnimation *sva = (DDSplitViewAnimation *)[animationTimer userInfo];
		[self setPosition:[sva finalPosition] ofDividerAtIndex:[sva dividerIndex]];
		
		[animationTimer invalidate];
		[animationTimer release];
		animationTimer = nil;
	}
	
	CGFloat initialPosition = [self positionOfDividerAtIndex:dividerIndex];
	
	DDSplitViewAnimation *sva = [[DDSplitViewAnimation alloc] initWithInitialPosition:initialPosition
																		finalPosition:position
																		 dividerIndex:dividerIndex
																			 duration:duration];
	
	animationTimer = [[NSTimer scheduledTimerWithTimeInterval:[sva iteration]
													   target:self
													 selector:@selector(updatePosition:)
													 userInfo:sva
													  repeats:YES] retain];
	
	[sva release];
}

- (void)updatePosition:(NSTimer *)aTimer
{
	DDSplitViewAnimation *sva = (DDSplitViewAnimation *)[aTimer userInfo];
	CGFloat newPosition = [sva calculateNewPosition];
	
	[self setPosition:newPosition ofDividerAtIndex:[sva dividerIndex]];
	
	if([sva isDone])
	{
		[animationTimer invalidate];
		[animationTimer release];
		animationTimer = nil;
	}
}

- (void)collapseSubview:(NSView *)subview
{
	[self collapseSubview:subview withAnimationDuration:0];
}

- (void)collapseSubview:(NSView *)subview withAnimationDuration:(NSTimeInterval)duration
{
	// Make sure subview is actually a subview
	int subviewIndex = 0;
	BOOL found = false;
	
	while(subviewIndex < [[self subviews] count] && !found)
	{
		if([[self subviews] objectAtIndex:subviewIndex] == subview)
		{
			found = YES;
		}
		else
		{
			subviewIndex++;
		}
	}
	
	if(!found)
	{
		// Subview doesn't exist in splitview!
		return;
	}
	
	// Make sure the subview isn't already collapsed
	if([self isSubviewCollapsed:subview])
	{
		// The subview is already collapsed!
		return;
	}
	
	// Make sure the subview is capable of collapsing
	BOOL canSubviewCollapse = NO;
	if([self delegate])
	{
		if([[self delegate] respondsToSelector:@selector(splitView:canCollapseSubview:)])
		{
			canSubviewCollapse = [[self delegate] splitView:self canCollapseSubview:subview];
		}
	}
	
	if(!canSubviewCollapse)
	{
		// This subview does not support collapsing!
		return;
	}
	
	if([self isVertical])
	{
		if(subviewIndex == 0)
		{
			if(duration > 0)
				[self setPosition:0 ofDividerAtIndex:0 withAnimationDuration:duration collapsedSubview:subview];
			else
				[self setPosition:0 ofDividerAtIndex:0];
		}
		else
		{
			NSRect frame = [self frame];
			CGFloat position = frame.size.width - [self dividerThickness];
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration collapsedSubview:subview];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
	}
	else
	{
		if(subviewIndex == 0)
		{
			if(duration > 0)
				[self setPosition:0 ofDividerAtIndex:0 withAnimationDuration:duration  collapsedSubview:subview];
			else
				[self setPosition:0 ofDividerAtIndex:0];
		}
		else
		{
			NSRect frame = [self frame];
			CGFloat position = frame.size.height - [self dividerThickness];
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration collapsedSubview:subview];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
	}
}

- (void)uncollapseSubview:(NSView *)subview
{
	[self uncollapseSubview:subview withAnimationDuration:0];
}

- (void)uncollapseSubview:(NSView *)subview withAnimationDuration:(NSTimeInterval)duration
{
	// Make sure subview is actually a subview
	int subviewIndex = 0;
	BOOL found = false;
	
	while(subviewIndex < [[self subviews] count] && !found)
	{
		if([[self subviews] objectAtIndex:subviewIndex] == subview)
		{
			found = YES;
		}
		else
		{
			subviewIndex++;
		}
	}
	
	if(!found)
	{
		// Subview doesn't exist in splitview!
		return;
	}
	
	// Make sure the subview is collapsed
	if(![self isSubviewCollapsed:subview])
	{
		// The subview is not collapsed!
		return;
	}
	
	if([self isVertical])
	{
		if(subviewIndex == 0)
		{
			CGFloat position;
			
			NSRect subviewFrame = [subview frame];
			if(subviewFrame.size.width == 0)
			{
				// When the subview is collapsable, then minPossiblePosition is simply zero.
				// This won't give us an uncollapsed subview though, so we need to invoke the delegate method.
				position = [self minPossiblePositionOfDividerAtIndex:0];
				if([[self delegate] respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)])
				{
					position = [[self delegate] splitView:self constrainMinCoordinate:position ofSubviewAt:1];
				}
			}
			else
			{
				position = subviewFrame.size.width;
			}
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
		else
		{
			CGFloat position;
			
			NSRect subviewFrame = [subview frame];
			if(subviewFrame.size.width == 0)
			{
				// When the subview is collapsable,
				// then maxPossiblePosition is simply selfFrame.size.width - dividerThickness.
				// This won't give us an uncollapsed subview though, so we need to invoke the delegate method.
				position = [self maxPossiblePositionOfDividerAtIndex:0];
				if([[self delegate] respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)])
				{
					position = [[self delegate] splitView:self constrainMaxCoordinate:position ofSubviewAt:1];
				}
			}
			else
			{
				NSRect selfFrame = [self frame];
				position = selfFrame.size.width - [self dividerThickness] - subviewFrame.size.width;
			}
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
	}
	else
	{
		if(subviewIndex == 0)
		{
			CGFloat position;
			
			NSRect subviewFrame = [subview frame];
			if(subviewFrame.size.height == 0)
			{
				// When the subview is collapsable, then minPossiblePosition is simply zero.
				// This won't give us an uncollapsed subview though, so we need to invoke the delegate method.
				position = [self minPossiblePositionOfDividerAtIndex:0];
				if([[self delegate] respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)])
				{
					position = [[self delegate] splitView:self constrainMinCoordinate:position ofSubviewAt:1];
				}
			}
			else
			{
				position = subviewFrame.size.height;
			}
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
		else
		{
			CGFloat position;
			
			NSRect subviewFrame = [subview frame];
			if(subviewFrame.size.height == 0)
			{
				// When the subview is collapsable,
				// then maxPossiblePosition is simply selfFrame.size.height - dividerThickness.
				// This won't give us an uncollapsed subview though, so we need to invoke the delegate method.
				position = [self maxPossiblePositionOfDividerAtIndex:0];
				if([[self delegate] respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)])
				{
					position = [[self delegate] splitView:self constrainMaxCoordinate:position ofSubviewAt:1];
				}
			}
			else
			{
				NSRect selfFrame = [self frame];
				position = selfFrame.size.height - [self dividerThickness] - subviewFrame.size.height;
			}
			
			if(duration > 0)
				[self setPosition:position ofDividerAtIndex:0 withAnimationDuration:duration];
			else
				[self setPosition:position ofDividerAtIndex:0];
		}
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation DDSplitViewAnimation

- (id)initWithInitialPosition:(CGFloat)ip
				finalPosition:(CGFloat)fp
				 dividerIndex:(NSInteger)di
					 duration:(NSTimeInterval)d
{
	if((self = [super init]))
	{
		initialPosition = ip;
		finalPosition = fp;
		duration = d;
		
		// Now calculate the iterations
		totalIterations = (int)(duration * 30);
		currentIteration = 0;
		
		iteration = duration / totalIterations;
		
		positionIterationChange = (finalPosition - initialPosition) / totalIterations;
	}
	return self;
}

- (id)initWithInitialPosition:(CGFloat)ip
				finalPosition:(CGFloat)fp
				 dividerIndex:(NSInteger)di
					 duration:(NSTimeInterval)d
					  subview:(NSView *)subview
{
	if((self = [super init]))
	{
		initialPosition = ip;
		finalPosition = fp;
		duration = d;
		
		viewToCollapse = subview;
		collapsedFrame = [subview frame];
		
		// Now calculate the iterations
		totalIterations = (int)(duration * 30);
		currentIteration = 0;
		
		iteration = duration / totalIterations;
		
		positionIterationChange = (finalPosition - initialPosition) / totalIterations;
	}
	return self;
}

- (CGFloat)initialPosition
{
	return initialPosition;
}
- (CGFloat)finalPosition
{
	return finalPosition;
}

- (NSInteger)dividerIndex
{
	return dividerIndex;
}

- (NSTimeInterval)duration
{
	return duration;
}
- (NSTimeInterval)iteration
{
	return iteration;
}

- (int)totalIterations
{
	return totalIterations;
}
- (int)currentIteration
{
	return currentIteration;
}

- (CGFloat)calculateNewPosition
{
	currentIteration++;
	
	return initialPosition + (currentIteration * positionIterationChange);
}

- (BOOL)isDone
{
	BOOL result = currentIteration >= totalIterations;
	
	if(result && viewToCollapse)
	{
		[viewToCollapse setHidden:YES];
		[viewToCollapse setFrame:collapsedFrame];
	}
	return result;
}

@end
