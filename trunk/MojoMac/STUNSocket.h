/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@class AsyncUdpSocket;
@class STUNMessage;
@class XMPPJID;
@class XMPPMessage;
@class STUNLogger;

enum RouterType
{
	ROUTER_TYPE_UNKNOWN                   = -1,
	ROUTER_TYPE_NONE                      =  0,
	ROUTER_TYPE_CONE_FULL                 =  1,
	ROUTER_TYPE_CONE_RESTRICTED           =  2,
	ROUTER_TYPE_CONE_PORT_RESTRICTED      =  3,
	ROUTER_TYPE_SYMMETRIC_FULL            =  4,
	ROUTER_TYPE_SYMMETRIC_RESTRICTED      =  5,
	ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED =  6
};
typedef enum RouterType RouterType;

#define STR_ROUTER_TYPE_UNKNOWN                    @"Unknown"
#define STR_ROUTER_TYPE_NONE                       @"None"
#define STR_ROUTER_TYPE_CONE_FULL                  @"Cone - Full"
#define STR_ROUTER_TYPE_CONE_RESTRICTED            @"Cone - Restricted"
#define STR_ROUTER_TYPE_CONE_PORT_RESTRICTED       @"Cone - Port Restricted"
#define STR_ROUTER_TYPE_SYMMETRIC_FULL             @"Symmetric - Full"
#define STR_ROUTER_TYPE_SYMMETRIC_RESTRICTED       @"Symmetric - Restricted"
#define STR_ROUTER_TYPE_SYMMETRIC_PORT_RESTRICTED  @"Symmetric - Port Restricted"

enum PortAllocationType
{
	PORT_ALLOCATION_TYPE_UNKNOWN  = -1,
	PORT_ALLOCATION_TYPE_PORT     =  0,
	PORT_ALLOCATION_TYPE_ADDRESS  =  1,
};
typedef enum PortAllocationType PortAllocationType;

#define STR_PORT_ALLOCATION_TYPE_UNKNOWN   @"Unknown"
#define STR_PORT_ALLOCATION_TYPE_PORT      @"Port Sensitive"
#define STR_PORT_ALLOCATION_TYPE_ADDRESS   @"Address Sensitive"


@interface STUNSocket : NSObject
{
	int attemptCount;
	int state;
	BOOL isClient;
	
	XMPPJID *jid;
	NSString *uuid;
	
	STUNMessage *currentStunMessage;
	NSString *currentStunMessageDestinationHost;
	UInt16 currentStunMessageDestinationPort;
	int currentStunMessageNumber;
	NSTimeInterval currentStunMessageElapsed;
	NSTimeInterval currentStunMessageTimeout;
	NSDate *currentStunMessageFirstSentTime;
	NSTimeInterval maxRtt;
	
	NSString *altStunServerIP;
	UInt16 altStunServerPort;
	
	RouterType local_routerType;
	NSString *local_externalIP;
	UInt16 local_externalPort;
	NSRange local_externalPortRange;
	PortAllocationType local_portAllocationType;
	
	RouterType remote_routerType;
	NSString *remote_externalIP;
	UInt16 remote_externalPort;
	NSRange remote_externalPortRange;
	
	UInt16 predictedPort1;
	UInt16 predictedPort2;
	UInt16 predictedPort3;
	UInt16 predictedPort4;
	
	AsyncUdpSocket *udpSocket;
	
	NSMutableArray *scanningSockets;
	
	id delegate;
	
	NSData *validationData;
	NSTimer *validationTimer;
	NSTimeInterval validationElapsed;
	NSTimeInterval validationTimeout;
	
	NSDate *restartIncomingValidationDate;
	
	BOOL readValidationFailed;
	BOOL readValidationComplete;
	BOOL writeValidationComplete;
	
	STUNLogger *logger;
	NSDate *startTime, *finishTime;
}

+ (BOOL)isNewStartStunMessage:(XMPPMessage *)msg;

- (id)initWithJID:(XMPPJID *)jid;
- (id)initWithStunMessage:(XMPPMessage *)message;

- (void)start:(id)delegate;

- (NSString *)uuid;

- (BOOL)isClient;

- (void)abort;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (STUNSocketDelegate)

- (void)stunSocket:(STUNSocket *)sender didSucceed:(AsyncUdpSocket *)socket;

- (void)stunSocketDidFail:(STUNSocket *)sender;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNXMPPMessage : NSObject
{
	XMPPJID *to;
	XMPPJID *from;
	NSString *uuid;
	
	NSString *type;
	NSString *version;
	
	RouterType routerType;
	NSString *ip;
	UInt16 port;
	NSRange portRange;
	
	NSString *errorMessage;
}

+ (BOOL)isStunInviteMessage:(XMPPMessage *)msg;

+ (STUNXMPPMessage *)messageFromMessage:(XMPPMessage *)msg;
+ (STUNXMPPMessage *)messageWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid;

- (id)initFromMessage:(XMPPMessage *)msg;
- (id)initWithType:(NSString *)type to:(XMPPJID *)to uuid:(NSString *)uuid;

- (XMPPJID *)to;
- (XMPPJID *)from;
- (NSString *)uuid;

- (NSString *)type;
- (NSString *)version;

- (RouterType)routerType;
- (void)setRouterType:(RouterType)routerType;

- (NSString *)ip;
- (void)setIP:(NSString *)ip;

- (UInt16)port;
- (void)setPort:(UInt16)port;

- (NSRange)portRange;
- (void)setPortRange:(NSRange)portRange;

- (NSString *)errorMessage;
- (void)setErrorMessage:(NSString *)msg;

- (NSXMLElement *)xmlElement;

@end