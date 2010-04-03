#import <Foundation/Foundation.h>
#import "TigerSupport.h"


@interface NSMutableData (RHMutableData)

- (void)trimStart:(NSUInteger)length;
- (void)trimEnd:(NSUInteger)length;

- (NSString *)stringValue;
- (NSString *)stringValueWithRange:(NSRange)subrange;
- (NSString *)stringValueWithEncoding:(NSStringEncoding)encoding;
- (NSString *)stringValueWithRange:(NSRange)subrange encoding:(NSStringEncoding)encoding;

- (NSRange)rangeOfData:(NSData *)data;

@end
