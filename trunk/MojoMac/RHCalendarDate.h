#import <Foundation/Foundation.h>


@interface NSCalendarDate (RHCalendarDate)

+ (NSCalendarDate *)calendarDateWithZuluDateString:(NSString *) zuluDateString;
- (NSString *)zuluDateString;

- (NSTimeInterval)intervalOfMinute;
- (NSTimeInterval)intervalOfDay;

@end
