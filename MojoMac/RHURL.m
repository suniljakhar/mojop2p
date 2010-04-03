#import "RHURL.h"


@implementation NSURL (RHURL)

+ (NSString *)urlEncodeValue:(NSString *)str
{
	if(str == nil) return nil;
	
	NSString *result = (NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
																		   (CFStringRef)str,
																		   NULL,
																		   CFSTR("?=&+"),
																		   kCFStringEncodingUTF8);
	return [result autorelease];
}

+ (NSString *)urlDecodeValue:(NSString *)str
{
	if(str == nil) return nil;
	
	NSString *result = (NSString *)CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
																			  (CFStringRef)str,
																			  CFSTR(""));
	return [result autorelease];
}

@end
