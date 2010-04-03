#import <Foundation/Foundation.h>


@interface NSURL (RHURL)

+ (NSString *)urlEncodeValue:(NSString *)str;
+ (NSString *)urlDecodeValue:(NSString *)str;

@end
