#import <Foundation/Foundation.h>
#import "HTTPResponse.h"

@class HTTPConnection;


@interface SearchResponse : NSObject <HTTPResponse>
{
	HTTPConnection *connection;
	NSThread *connectionThread;
	NSArray *connectionRunLoopModes;
	
	NSData *responseData;
	NSUInteger responseOffset;
}

- (id)initWithQuery:(NSDictionary *)query forConnection:(HTTPConnection *)connection runLoopModes:(NSArray *)modes;

@end
