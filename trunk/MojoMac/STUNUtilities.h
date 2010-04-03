/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@protocol STUNAttribute;
@class STUNAddressAttribute;
@class STUNLogger;


@interface STUNUtilities : NSObject

+ (UInt16)randomPortNumber;

+ (NSData *)generateTrasactionID;

+ (void)sendStunFeedback:(STUNLogger *)logger;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

enum StunMessageType
{
	STUN_BINDING_REQUEST                = 0x0001,
	STUN_BINDING_RESPONSE               = 0x0101,
	STUN_BINDING_ERROR_RESPONSE         = 0x0111,
	STUN_SHARED_SECRET_REQUEST          = 0x0002,
	STUN_SHARED_SECRET_RESPONSE         = 0x0102,
	STUN_SHARED_SECRET_ERROR_RESPONSE   = 0x0112
};
typedef enum StunMessageType StunMessageType;

enum StunAttributeType
{
	STUN_ATTR_MAPPED_ADDRESS            = 0x0001,
	STUN_ATTR_RESPONSE_ADDRESS          = 0x0002,
	STUN_ATTR_CHANGE_REQUEST            = 0x0003,
	STUN_ATTR_SOURCE_ADDRESS            = 0x0004,
	STUN_ATTR_CHANGED_ADDRESS           = 0x0005,
	STUN_ATTR_USERNAME                  = 0x0006,
	STUN_ATTR_PASSWORD                  = 0x0007,
	STUN_ATTR_MESSAGE_INTEGRITY         = 0x0008,
	STUN_ATTR_ERROR_CODE                = 0x0009,
	STUN_ATTR_UNKNOWN_ATTRIBUTES        = 0x000A,
	STUN_ATTR_REFLECTED_FROM            = 0x000B,
	STUN_ATTR_XOR_MAPPED_ADDRESS        = 0x8020,
};
typedef enum StunAttributeType StunAttributeType;

enum StunErrorCode
{
	STUN_ERROR_BAD_REQUEST              = 400,
	STUN_ERROR_UNAUTHORIZED             = 401,
	STUN_ERROR_UNKNOWN_ATTRIBUTE        = 420,
	STUN_ERROR_STALE_CREDENTIALS        = 430,
	STUN_ERROR_INTEGRITY_CHECK_FAILURE  = 431,
	STUN_ERROR_MISSING_USERNAME         = 432,
	STUN_ERROR_USE_TLS                  = 433,
	STUN_ERROR_SERVER_ERROR             = 500,
	STUN_ERROR_GLOBAL_FAILURE           = 600
};
typedef enum StunErrorCode StunErrorCode;


@interface STUNMessage : NSObject
{
	StunMessageType type;
	
	NSData *transactionID;
	
	NSMutableArray *attributes;
}

+ (STUNMessage *)parseMessage:(NSData *)data;

- (id)initWithType:(StunMessageType)type;
- (id)initWithType:(StunMessageType)type transactionID:(NSData *)tid;

- (NSData *)transactionID;

- (void)addAttribute:(id<STUNAttribute>)attribute;

- (STUNAddressAttribute *)mappedAddress;
- (STUNAddressAttribute *)responseAddress;
- (STUNAddressAttribute *)changedAddress;
- (STUNAddressAttribute *)sourceAddress;
- (STUNAddressAttribute *)reflectedFrom;
- (STUNAddressAttribute *)xorMappedAddress;

- (NSData *)messageData;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol STUNAttribute

- (StunAttributeType)type;
- (UInt16)attributeLength;
- (NSData *)attributeData;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNAddressAttribute : NSObject <STUNAttribute>
{
	StunAttributeType type;
	UInt16 port;
	NSString *address;
	
	NSData *xorData;
}

+ (STUNAddressAttribute *)parseAttributeWithType:(StunAttributeType)type
										  length:(unsigned)length
										   value:(NSData *)data
										 xorData:(NSData *)xorData;

- (id)initWithType:(StunAttributeType)type address:(NSString *)ip port:(UInt16)port xorData:(NSData *)xorData;

- (StunAttributeType)type;
- (UInt16)attributeLength;
- (NSData *)attributeData;

- (UInt16)port;
- (NSString *)address;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNChangeAttribute : NSObject <STUNAttribute>
{
	UInt32 flags;
}

+ (STUNChangeAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data;

- (id)initWithChangeIP:(BOOL)ipFlag changePort:(BOOL)portFlag;

- (StunAttributeType)type;
- (UInt16)attributeLength;
- (NSData *)attributeData;

- (BOOL)changeIP;
- (BOOL)changePort;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNErrorAttribute : NSObject <STUNAttribute>
{
	unsigned errorCode;
	NSString *reasonPhrase;
}

+ (STUNErrorAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data;

- (id)initWithErrorCode:(unsigned)ec reasonPhrase:(NSString *)rp;

- (StunAttributeType)type;
- (UInt16)attributeLength;
- (NSData *)attributeData;

- (unsigned)errorCode;
- (NSString *)reasonPhrase;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNStringAttribute : NSObject <STUNAttribute>
{
	StunAttributeType type;
	NSString *str;
}

+ (STUNStringAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data;

- (id)initWithType:(StunAttributeType)type string:(NSString *)str;

- (StunAttributeType)type;
- (UInt16)attributeLength;
- (NSData *)attributeData;

- (NSString *)stringValue;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNPortPredictionLogger : NSObject
{
	UInt16 localPort;
	UInt16 reportedPort1;
	UInt16 reportedPort2;
	UInt16 reportedPort3;
	UInt16 reportedPort4;
	UInt16 predictedPort;
	NSRange predictedPortRange;
}

- (id)initWithLocalPort:(UInt16)port;

- (UInt16)localPort;

- (UInt16)reportedPort1;
- (void)setReportedPort1:(UInt16)port;

- (UInt16)reportedPort2;
- (void)setReportedPort2:(UInt16)port;

- (UInt16)reportedPort3;
- (void)setReportedPort3:(UInt16)port;

- (UInt16)reportedPort4;
- (void)setReportedPort4:(UInt16)port;

- (UInt16)predictedPort;
- (void)setPredictedPort:(UInt16)port;

- (NSRange)predictedPortRange;
- (void)setPredictedPortRange:(NSRange)portRange;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

enum TraversalAlgorithm {
	TRAVERSAL_ALGORITHM_STD      = 0,
	TRAVERSAL_ALGORITHM_PSSTUN1  = 1,
	TRAVERSAL_ALGORITHM_PSSTUN2  = 2
};
typedef enum TraversalAlgorithm TraversalAlgorithm;

enum STUNValidation {
	STUN_VALIDATION_FAILURE  = -1,
	STUN_VALIDATION_NONE     =  0,
	STUN_VALIDATION_SUCCESS  =  1
};
typedef enum STUNValidation STUNValidation;

@interface STUNLogger : NSObject
{
	NSString *stunUUID;
	NSString *stunVersion;
	
	NSString *routerManufacturer;
	
	NSString *routerMapping;
	NSString *routerFiltering;
	
	BOOL xorNeeded;
	
	TraversalAlgorithm traversalAlgorithm;
	
	NSMutableArray *portPredictions;
	
	NSTimeInterval duration;
	
	BOOL success;
	int cycle;
	
	STUNValidation readValidation;
	STUNValidation writeValidation;
	
	NSString *failureReason;
	
	NSMutableString *trace;
}

+ (NSString *)machineUUID;

- (id)initWithSTUNUUID:(NSString *)uuid version:(NSString *)version;

- (void)setRouterManufacturer:(NSString *)manufacturer;

- (void)setRouterMapping:(NSString *)routerMapping;
- (void)setRouterFiltering:(NSString *)routerFiltering;

- (void)setXorNeeded:(BOOL)flag;

- (void)setTraversalAlgorithm:(TraversalAlgorithm)talg;

- (void)addPortPredictionLogger:(STUNPortPredictionLogger *)ppLogger;

- (void)setDuration:(NSTimeInterval)total;

- (void)setSuccess:(BOOL)flag;
- (void)setSuccessCycle:(int)successCycle;

- (void)setReadValidation:(BOOL)flag;
- (void)setWriteValidation:(BOOL)flag;

- (void)setFailureReason:(NSString *)reason;

- (void)addTraceMethod:(NSString *)method;
- (void)addTraceMessage:(NSString *)message, ...;

- (NSData *)postData;

@end
