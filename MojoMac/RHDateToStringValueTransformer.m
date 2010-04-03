#import "RHDateToStringValueTransformer.h"


@implementation RHDateToStringValueTransformer

// CLASS METHODS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;   
}

// TRANSFORMING WORK
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)transformedValue:(id)value;
{
	if(![value isKindOfClass:[NSDate class]])
		return nil;
	
	NSCalendarDate *date;
	if([value isKindOfClass:[NSCalendarDate class]])
		date = value;
	else
		date = [value dateWithCalendarFormat:nil timeZone:nil];
	
	int today = [[NSCalendarDate calendarDate] dayOfCommonEra];
	int dateDay = [date dayOfCommonEra];
	
	if(dateDay == today)
	{
		NSString *todayStr = NSLocalizedString(@"Today", @"Designation for the current day");
		
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterNoStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [NSString stringWithFormat:@"%@ %@", todayStr, [df stringFromDate:date]]; 
	}
	else if(dateDay == (today-1))
	{
		NSString *yesterdayStr = NSLocalizedString(@"Yesterday", @"Designation for the previous day");
		
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterNoStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [NSString stringWithFormat:@"%@ %@", yesterdayStr, [df stringFromDate:date]]; 
	}
	else
	{
		NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
		[df setFormatterBehavior:NSDateFormatterBehavior10_4];
		[df setDateStyle:NSDateFormatterMediumStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		return [df stringFromDate:date];
	}
}

@end
