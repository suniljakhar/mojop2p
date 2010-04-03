/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@class AsyncSocket;
@class XMPPJID;
@class XMPPMessage;
@class STUNTLogger;
@class TCMPortMapping;

@interface STUNTSocket : NSObject
{
	int attemptCount;
	int state;
	BOOL isClient;
	
	XMPPJID *jid;
	NSString *uuid;
	
	TCMPortMapping *portMapping;
	
	NSString *local_externalIP;
	int local_serverPort;
	int local_mappedServerPort;
	int local_internalPort;
	int local_predictedPort;
	
	NSString *remote_stuntVersion;
	NSString *remote_externalIP;
	int remote_serverPort;
	int remote_predictedPort;
	
	AsyncSocket *asock;
	AsyncSocket *bsock;
	AsyncSocket *psock;
	AsyncSocket *qsock;
	AsyncSocket *rsock;
	AsyncSocket *fsock;
	
	id delegate;
	
	STUNTLogger *logger;
	NSDate *startTime, *finishTime;
}

+ (BOOL)isNewStartStuntMessage:(XMPPMessage *)msg;

+ (BOOL)handleSTUNTRequest:(CFHTTPMessageRef)request fromSocket:(AsyncSocket *)sock;

- (id)initWithJID:(XMPPJID *)jid;
- (id)initWithStuntMessage:(XMPPMessage *)message;

- (void)start:(id)delegate;

- (NSString *)uuid;

- (BOOL)isClient;

- (void)abort;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (STUNTSocketDelegate)

- (void)stuntSocket:(STUNTSocket *)sender didSucceed:(AsyncSocket *)connectedSocket;

- (void)stuntSocketDidFail:(STUNTSocket *)sender;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNTMessage : NSObject
{
	XMPPJID *to;
	XMPPJID *from;
	NSString *uuid;
	
	NSString *type;
	NSString *version;
	
	NSString *ip4;
	NSString *ip6;
	int predictedPort;
	int serverPort;
	
	NSString *errorMessage;
}

+ (BOOL)isStuntInviteMessage:(XMPPMessage *)msg;

+ (STUNTMessage *)messageFromMessage:(XMPPMessage *)msg;
+ (STUNTMessage *)messageWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid;

- (id)initFromMessage:(XMPPMessage *)msg;
- (id)initWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid;

- (XMPPJID *)to;
- (XMPPJID *)from;
- (NSString *)uuid;

- (NSString *)type;
- (NSString *)version;

- (NSString *)ip4;
- (void)setIP4:(NSString *)ip4;

- (NSString *)ip6;
- (void)setIP6:(NSString *)ip6;

- (int)predictedPort;
- (void)setPredictedPort:(int)port;

- (int)serverPort;
- (void)setServerPort:(int)port;

- (NSString *)errorMessage;
- (void)setErrorMessage:(NSString *)msg;

- (NSXMLElement *)xmlElement;

@end