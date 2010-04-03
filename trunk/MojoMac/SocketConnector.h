#import <Foundation/Foundation.h>
#import "TigerSupport.h"

@class AsyncSocket;


@interface SocketConnector : NSObject
{
	id delegate;
	
	NSObject *tag;
	
	NSArray *sortedAddresses;
	AsyncSocket *asyncSocket;
}

- (id)initWithAddresses:(NSArray *)addresses;

- (NSObject *)tag;
- (void)setTag:(NSObject *)tag;

- (void)start:(id)delegate;
- (void)abort;

@end

@interface NSObject (SocketConnectorDelegate)

- (void)socketConnector:(SocketConnector *)sc didConnect:(AsyncSocket *)socket;
- (void)socketConnectorDidNotConnect:(SocketConnector *)sc;

@end
