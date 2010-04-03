#import "RHDate.h"

@implementation NSDate (RHDate)

// FOR COMPARING DATES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns whether or not the current calendarDate is earlier then the given calendarDate.
 * Note: If they represent the same date in time, this method returns false.
 * Note: Doesn't take into effect the timeZone representation. Just the internal NSDate absolute time.
**/
- (BOOL)isEarlierDate:(NSDate *)anotherDate
{
	return [self timeIntervalSinceDate:anotherDate] < 0;
}

/**
 * Returns whether or not the current calendarDate is later then the given calendarDate.
 * Note: If they represent the same date in time, this method returns false.
 * Note: Doesn't take into effect the timeZone representation. Just the internal NSDate absolute time.
**/
- (BOOL)isLaterDate:(NSDate *)anotherDate
{
	return [self timeIntervalSinceDate:anotherDate] > 0;
}

@end
