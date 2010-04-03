#import <Foundation/Foundation.h>
#import "TigerSupport.h"

@class AsyncSocket;
@class GatewayHTTPConnection;
@class XMPPJID;


@interface GatewayHTTPServer : NSObject
{
	NSString *remoteHost;
	UInt16 remotePort;
	
	XMPPJID *jid;
	
	AsyncSocket *localSocket;
	
	NSMutableArray *connections;
	NSMutableArray *unavailableRemoteSockets;
	NSMutableArray *availableRemoteTcpSockets;
	NSMutableArray *availableRemoteUdpSockets;
	NSMutableArray *availableRemoteProxySockets;
	NSMutableArray *stuntSockets;
	NSMutableArray *stunSockets;
	NSMutableArray *turnSockets;
	
	NSMutableArray *waitStuntTimers;
	NSMutableArray *waitStunTimers;
	NSMutableArray *waitTurnTimers;
	
	BOOL isSecure;
	
	NSString *username;
	NSString *password;
	
	UInt16 stuntSuccessCount;
	UInt16 stuntFailureCount;
	UInt16 stunSuccessCount;
	UInt16 stunFailureCount;
	UInt16 turnSuccessCount;
	UInt16 turnFailureCount;
	
	NSString *uuid;
	
	BOOL remoteHostSupportsSTUN;
	BOOL remoteHostSupportsTURN;
}
- (id)initWithHost:(NSString *)host port:(UInt16)port;
- (id)initWithJID:(XMPPJID *)jid;

- (UInt16)localPort;

- (void)setIsSecure:(BOOL)useSSL;
- (void)setUsername:(NSString *)username password:(NSString *)password;

- (NSString *)username;
- (NSString *)password;

- (void)requestNewRemoteSocket:(GatewayHTTPConnection *)connection;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface GatewayHTTPConnection : NSObject
{
	AsyncSocket *remoteSocket;
	AsyncSocket *localSocket;
	GatewayHTTPServer *server;
	
	CFHTTPMessageRef request;
	CFHTTPMessageRef response;
	
	BOOL isResponseConnectionClose;
	BOOL isProcessingRequestOrResponse;
	
	unsigned fileSizeInBytes;
	unsigned totalBytesReceived;
	
	BOOL usingChunkedTransfer;
	unsigned chunkedTransferStage;
	unsigned chunkSize;
	NSMutableData *chunkedData;
	
	BOOL intercepting;
	CFHTTPAuthenticationRef auth;
}
- (id)initWithLocalSocket:(AsyncSocket *)localSocket forServer:(GatewayHTTPServer *)myServer;

- (AsyncSocket *)remoteSocket;
- (void)setRemoteSocket:(AsyncSocket *)remoteSocket;

- (BOOL)isRemoteSocketReusable;

@end
