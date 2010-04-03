#import <Foundation/Foundation.h>

@interface NSDate (RHDate)

// For comparing dates
- (BOOL)isEarlierDate:(NSDate *)anotherDate;
- (BOOL)isLaterDate:(NSDate *)anotherDate;

@end
