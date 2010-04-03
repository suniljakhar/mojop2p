/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@class STUNTLogger;


@interface STUNTUtilities : NSObject

+ (int)randomPortNumber;

+ (NSString *)globaIPv6Address;

+ (NSData *)downloadURL:(NSURL *)url onLocalPort:(int)localPortNumber timeout:(NSTimeInterval)connectTimeout;

+ (void)sendStuntFeedback:(STUNTLogger *)logger;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface STUNTPortPredictionLogger : NSObject
{
	UInt16 localPort;
	UInt16 reportedPort1;
	UInt16 reportedPort2;
	UInt16 predictedPort1;
	UInt16 predictedPort2;
}

- (id)initWithLocalPort:(UInt16)port;

- (UInt16)localPort;

- (UInt16)reportedPort1;
- (void)setReportedPort1:(UInt16)port;

- (UInt16)reportedPort2;
- (void)setReportedPort2:(UInt16)port;

- (UInt16)predictedPort1;
- (void)setPredictedPort1:(UInt16)port;

- (UInt16)predictedPort2;
- (void)setPredictedPort2:(UInt16)port;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STUNT_VALIDATION_FAILURE  -1
#define STUNT_VALIDATION_NONE      0
#define STUNT_VALIDATION_SUCCESS   1

@interface STUNTLogger : NSObject
{
	NSString *stuntUUID;
	NSString *stuntVersion;
	
	NSString *routerManufacturer;
	
	NSMutableArray *portPredictions;
	
	BOOL portMappingAvailable;
	NSString *portMappingProtocol;
	
	BOOL connectionViaServer;
	
	NSTimeInterval duration;
	
	BOOL success;
	int cycle;
	int state;
	
	int validation;
	
	NSString *failureReason;
	
	NSMutableString *trace;
}

+ (NSString *)machineUUID;

- (id)initWithSTUNTUUID:(NSString *)uuid version:(NSString *)version;

- (void)setRouterManufacturer:(NSString *)manufacturer;

- (void)addPortPredictionLogger:(STUNTPortPredictionLogger *)ppLogger;

- (void)setPortMappingAvailable:(BOOL)flag;
- (void)setPortMappingProtocol:(NSString *)protocol;

- (void)setConnectionViaServer:(BOOL)flag;

- (void)setDuration:(NSTimeInterval)total;

- (void)setSuccess:(BOOL)flag;
- (void)setSuccessCycle:(int)successCycle;
- (void)setSuccessState:(int)successState;

- (void)setValidation:(int)validation;

- (void)setFailureReason:(NSString *)reason;

- (void)addTraceMethod:(NSString *)method;
- (void)addTraceMessage:(NSString *)message, ...;

- (NSData *)postData;

@end

