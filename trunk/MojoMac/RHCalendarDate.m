#import "RHCalendarDate.h"


@implementation NSCalendarDate (RHCalendarDate)

// FOR WORKING WITH ZULU TIME/DATE FORMATS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates an NSCalendarDate object from a string representing a Zulu formatted date and time.
**/
+ (NSCalendarDate *)calendarDateWithZuluDateString:(NSString *) zuluDateString
{
	// NSCalendarDate doesn't understand Zulu-format strings
	// ...so strip trailing "Z" and replace with offset from GMT (+0)
	NSString *str = [NSString stringWithFormat:@"%@+0", [zuluDateString substringToIndex:[zuluDateString length]-2]];
	
	// This is the defined Zulu date format
	NSString *dateFormat = @"%Y%m%d%H%M%S%z";
	
	// Now create the object, and then revert it's calendar format (for output) to the default
	NSCalendarDate *result = [NSCalendarDate dateWithString:str calendarFormat:dateFormat];
	[result setCalendarFormat:nil];
	
	return result;
}

/**
 * Returns a Zulu-format date string (e.g. '20060622164012Z')
**/
- (NSString *)zuluDateString
{
	NSDictionary *locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
	NSString *dateFormat = @"%Y%m%d%H%M%SZ";
	return [self descriptionWithCalendarFormat:dateFormat timeZone:[NSTimeZone timeZoneWithName:@"GMT"] locale:locale];
}

// FOR EXTRACTING PRECISION DATE COMPONENTS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*!
 * Returns an NSTimeInterval within the minute.
 * This can be used to determine both the number of seconds, and milliseconds, of the time within the current minute.
 * IE - if the time is 5:42:36.238 AM, this method would return 36.238.
 * 
 * typedef double NSTimeInterval: Always in seconds; yields submillisecond precision...
 */
- (NSTimeInterval)intervalOfMinute
{
	double totalWithMillis = [self timeIntervalSinceReferenceDate] + [[self timeZone] secondsFromGMT];
	int totalWithoutMillis = (int)totalWithMillis;
	
	double sec = totalWithoutMillis % 60;
	double mil = totalWithMillis - totalWithoutMillis;
	
	return sec + mil;
}

/*!
 * Returns an NSTimeInterval within the day.
 * This can be used to determine both the number of seconds, and milliseconds, of the time within the current day.
 * IE - if the time is 12:01:02.003 AM, this method would return 62.003.
 * 
 * typedef double NSTimeInterval: Always in seconds; yields submillisecond precision...
 */
- (NSTimeInterval)intervalOfDay
{
	double totalWithMillis = [self timeIntervalSinceReferenceDate] + [[self timeZone] secondsFromGMT];
	int totalWithoutMillis = (int)totalWithMillis;
	
	double sec = totalWithoutMillis % 86400;
	double mil = totalWithMillis - totalWithoutMillis;
	
	return sec + mil;
}

@end
