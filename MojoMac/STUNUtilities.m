/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "STUNUtilities.h"
#import "DDNumber.h"
#import "RHURL.h"
#import "MojoDefinitions.h"
#import "TigerSupport.h"

#import <arpa/inet.h>

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 3
#endif
#include "DDLog.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNUtilities

/**
 * Returns a random port number is the range (8001 - 63024) inclusive.
**/
+ (UInt16)randomPortNumber
{
	return 8001 + (arc4random() % (63025 - 8001));
}

/**
 * Creates a random transaction ID with the help of the CFUUID class.
**/
+ (NSData *)generateTrasactionID
{
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	CFUUIDBytes uuidBytes = CFUUIDGetUUIDBytes(uuid);
	
	NSData *result = [NSData dataWithBytes:&uuidBytes length:sizeof(CFUUIDBytes)];
	
	CFRelease(uuid);
	
	return result;
}

+ (void)sendStunFeedback:(STUNLogger *)logger
{
	if(![[NSUserDefaults standardUserDefaults] boolForKey:PREFS_STUNT_FEEDBACK]) return;
	
	NSData *postData = [logger postData];
	NSString *lengthStr = [NSString stringWithFormat:@"%qu", (UInt16)[postData length]];
	
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:@"http://www.deusty.com/stun/feedback.php"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:lengthStr forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPBody:postData];
	
	NSURLDownload *urlDownload;
	urlDownload = [[NSURLDownload alloc] initWithRequest:request delegate:self];
	
	// We release urlDownload within the delegate methods
}

+ (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	[download autorelease];
	DDLogError(@"STUNUtilities: Failed sending anonymous STUN protocol statistics.");
}

+ (void)downloadDidFinish:(NSURLDownload *)download
{
	[download autorelease];
	DDLogInfo(@"STUNUtilities: Finished sending anonymous STUN protocol statistics.");
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNMessage

+ (STUNMessage *)parseMessage:(NSData *)data
{
	if([data length] < 20)
	{
		DDLogWarn(@"STUNMessage: parseMessage: data length < 20");
		return nil;
	}
	
	UInt16 msgType   = [NSNumber extractUInt16FromData:data atOffset:0 andConvertFromNetworkOrder:YES];
	UInt16 msgLength = [NSNumber extractUInt16FromData:data atOffset:2 andConvertFromNetworkOrder:YES];
	
	if (msgType != STUN_BINDING_REQUEST        &&
		msgType != STUN_BINDING_RESPONSE       &&
		msgType != STUN_BINDING_ERROR_RESPONSE &&
		msgType != STUN_SHARED_SECRET_REQUEST  &&
		msgType != STUN_SHARED_SECRET_RESPONSE &&
		msgType != STUN_SHARED_SECRET_ERROR_RESPONSE)
	{
		DDLogWarn(@"STUNMessage: parseMessage: unknown stun message type: %hu", msgType);
		return nil;
	}
	
	if(msgLength != [data length] - 20)
	{
		DDLogWarn(@"STUNMessage: parseMessage: parsed msgLength and data length differ");
		return nil;
	}
	
	void *pBytes = (void *)([data bytes] + 4);
	NSData *transactionID = [NSData dataWithBytes:pBytes length:16];
	
	STUNMessage *result = [[STUNMessage alloc] initWithType:msgType transactionID:transactionID];
	
	int offset = 20;
	while(offset + 4 < [data length])
	{
		UInt16 attrType   = [NSNumber extractUInt16FromData:data atOffset:offset+0 andConvertFromNetworkOrder:YES];
		UInt16 attrLength = [NSNumber extractUInt16FromData:data atOffset:offset+2 andConvertFromNetworkOrder:YES];
		
		if(offset + 4 + attrLength > [data length])
		{
			DDLogWarn(@"STUNMessage: parseMessage: incorrectly sized data");
			break;
		}
		
		void *pSubBytes = (void *)([data bytes] + offset + 4);
		NSData *subdata = [NSData dataWithBytesNoCopy:pSubBytes length:attrLength freeWhenDone:NO];
		
		if (attrType == STUN_ATTR_MAPPED_ADDRESS   ||
			attrType == STUN_ATTR_RESPONSE_ADDRESS ||
			attrType == STUN_ATTR_SOURCE_ADDRESS   ||
			attrType == STUN_ATTR_CHANGED_ADDRESS  ||
			attrType == STUN_ATTR_REFLECTED_FROM    )
		{
			STUNAddressAttribute *attr = [STUNAddressAttribute parseAttributeWithType:attrType
																			   length:attrLength
																				value:subdata
																			  xorData:nil];
			if(attr) [result addAttribute:attr];
		}
		else if(attrType == STUN_ATTR_XOR_MAPPED_ADDRESS)
		{
			STUNAddressAttribute *attr = [STUNAddressAttribute parseAttributeWithType:attrType
																			   length:attrLength
																				value:subdata
																			  xorData:transactionID];
			if(attr) [result addAttribute:attr];
		}
		else if(attrType == STUN_ATTR_CHANGE_REQUEST)
		{
			STUNChangeAttribute *attr = [STUNChangeAttribute parseAttributeWithType:attrType
																			 length:attrLength
																			  value:subdata];
			if(attr) [result addAttribute:attr];
		}
		else if(attrType == STUN_ATTR_ERROR_CODE)
		{
			STUNErrorAttribute *attr = [STUNErrorAttribute parseAttributeWithType:attrType
																		   length:attrLength
																			value:subdata];
			if(attr) [result addAttribute:attr];
		}
		else if(attrType == STUN_ATTR_USERNAME || attrType == STUN_ATTR_PASSWORD)
		{
			STUNStringAttribute *attr = [STUNStringAttribute parseAttributeWithType:attrType
																			 length:attrLength
																			  value:subdata];
			if(attr) [result addAttribute:attr];
		}
		else
		{
			DDLogWarn(@"STUNMessage: Skipping unknown attribute: %hu", attrType);
		}
		
		offset += 4 + attrLength;
	}
	
	return [result autorelease];
}

- (id)initWithType:(StunMessageType)typeParam
{
	if((self = [super init]))
	{
		type = typeParam;
		transactionID = [[STUNUtilities generateTrasactionID] retain];
		
		attributes = [[NSMutableArray alloc] initWithCapacity:0];
	}
	return self;
}

- (id)initWithType:(StunMessageType)typeParam transactionID:(NSData *)tid
{
	if((self = [super init]))
	{
		type = typeParam;
		transactionID = [tid copy];
		
		attributes = [[NSMutableArray alloc] initWithCapacity:0];
	}
	return self;
}

- (void)dealloc
{
	[transactionID release];
	[attributes release];
	[super dealloc];
}

- (NSData *)transactionID
{
	return transactionID;
}

- (void)addAttribute:(id<STUNAttribute>)attribute
{
	[attributes addObject:attribute];
}

- (id<STUNAttribute>)attributeWithType:(StunAttributeType)attrType
{
	int i;
	for(i = 0; i < [attributes count]; i++)
	{
		id<STUNAttribute> attribute = [attributes objectAtIndex:i];
		
		if([attribute type] == attrType)
		{
			return (STUNAddressAttribute *)attribute;
		}
	}
	
	return nil;
}

- (STUNAddressAttribute *)mappedAddress
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_MAPPED_ADDRESS];
}

- (STUNAddressAttribute *)responseAddress
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_RESPONSE_ADDRESS];
}

- (STUNAddressAttribute *)changedAddress
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_CHANGED_ADDRESS];
}

- (STUNAddressAttribute *)sourceAddress
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_SOURCE_ADDRESS];
}

- (STUNAddressAttribute *)reflectedFrom
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_REFLECTED_FROM];
}

- (STUNAddressAttribute *)xorMappedAddress
{
	return (STUNAddressAttribute *)[self attributeWithType:STUN_ATTR_XOR_MAPPED_ADDRESS];
}

- (NSData *)messageData
{
	int i;
	
	UInt16 length = 0;
	for(i = 0; i < [attributes count]; i++)
	{
		length += [[attributes objectAtIndex:i] attributeLength];
	}
	
	NSMutableData *result = [NSMutableData dataWithCapacity:(20 + length)];
	
	UInt16 type16 = htons(type);
	[result appendBytes:&type16 length:sizeof(type16)];
	
	UInt16 nLength = htons(length);
	[result appendBytes:&nLength length:sizeof(nLength)];
	
	[result appendData:transactionID];
	
	for(i = 0; i < [attributes count]; i++)
	{
		[result appendData:[[attributes objectAtIndex:i] attributeData]];
	}
	
	return result;
}

- (NSString *)description
{
	NSMutableString *result = [NSMutableString stringWithCapacity:25];
	
	NSString *typeStr = nil;
	
	switch(type)
	{
		case STUN_BINDING_REQUEST              : typeStr = @"Binding-Request";               break;
		case STUN_BINDING_RESPONSE             : typeStr = @"Binding-Response";              break;
		case STUN_BINDING_ERROR_RESPONSE       : typeStr = @"Binding-Error-Response";        break;
		case STUN_SHARED_SECRET_REQUEST        : typeStr = @"Shared-Secret-Request";         break;
		case STUN_SHARED_SECRET_RESPONSE       : typeStr = @"Shared-Secret-Response";        break;
		case STUN_SHARED_SECRET_ERROR_RESPONSE : typeStr = @"Shared-Secret-Error-Response";  break;
		default                                : typeStr = @"Unknown";                       break;
	}
	
	[result appendFormat:@"STUNMessage: type:%@ id:%@", typeStr, transactionID];
	
	int i;
	for(i = 0; i < [attributes count]; i++)
	{
		[result appendString:@"\n"];
		[result appendString:[[attributes objectAtIndex:i] description]];
	}
	
	return result;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNAddressAttribute

/**
 * Attempts to parse the given attribute data. If unsuccessful, returns nil.
 * It is assumed the given StunAttributeType is proper for this type of attribute.
 * It is assumed the given data is the same size as the given length.
 * The data should point to the attribute value. It should not include the already parsed attribute headers.
 * The length is checked to make sure it's the proper size for this type of attribute.
 * Pass xorData only if the StunAttributeType is an XOR type.
**/
+ (STUNAddressAttribute *)parseAttributeWithType:(StunAttributeType)type
										  length:(unsigned)length
										   value:(NSData *)data
										 xorData:(NSData *)xorData;
{
	if(length != 8)
	{
		DDLogWarn(@"STUNAddressAttribute: parseAttribute: length != 8");
		return nil;
	}
	
	UInt8 family = [NSNumber extractUInt8FromData:data atOffset:1];
	
	if(family != 0x01)
	{
		DDLogWarn(@"STUNAddressAttribute: parseAttribute: family != 0x01");
		return nil;
	}
	
	if(xorData != nil && [xorData length] < 4)
	{
		DDLogWarn(@"STUNAddressAttribute: parseAttribute: invalid xor data");
		return nil;
	}
	
	UInt16 port;
	char addrBuf[INET_ADDRSTRLEN];
	
	if(xorData == nil)
	{
		port = [NSNumber extractUInt16FromData:data atOffset:2 andConvertFromNetworkOrder:YES];
		
		const void *pAddr = [data bytes] + 4;
		
		if(inet_ntop(AF_INET, pAddr, addrBuf, sizeof(addrBuf)) == NULL)
		{
			DDLogWarn(@"STUNAddressAttribute: parseAttribute: inet_ntop failed");
			return nil;
		}
	}
	else
	{
		UInt16 xor16 = [NSNumber extractUInt16FromData:xorData atOffset:0 andConvertFromNetworkOrder:NO];
		UInt32 xor32 = [NSNumber extractUInt32FromData:xorData atOffset:0 andConvertFromNetworkOrder:NO];
		
		UInt16 xPort = [NSNumber extractUInt16FromData:data atOffset:2 andConvertFromNetworkOrder:NO];
		UInt32 xAddr = [NSNumber extractUInt32FromData:data atOffset:4 andConvertFromNetworkOrder:NO];
		
		port = ntohs(xPort ^ xor16);
		
		UInt32 hAddr = (xAddr ^ xor32);
		
		if(inet_ntop(AF_INET, &hAddr, addrBuf, sizeof(addrBuf)) == NULL)
		{
			DDLogWarn(@"STUNAddressAttribute: parseAttribute: inet_ntop failed");
			return nil;
		}
	}
	
	NSString *addr = [NSString stringWithCString:addrBuf encoding:NSASCIIStringEncoding];
	
	STUNAddressAttribute *result = [[STUNAddressAttribute alloc] initWithType:type
																	  address:addr
																		 port:port
																	  xorData:xorData];
	return [result autorelease];
}

- (id)initWithType:(StunAttributeType)typeParam address:(NSString *)ip port:(UInt16)portParam xorData:(NSData *)data
{
	if((self = [super init]))
	{
		type = typeParam;
		address = [ip copy];
		port = portParam;
		xorData = [data copy];
	}
	return self;
}

- (void)dealloc
{
	[address release];
	[xorData release];
	[super dealloc];
}

- (StunAttributeType)type
{
	return type;
}

/**
 * Returns the length of the entire attribute, including the header.
**/
- (UInt16)attributeLength
{
	// 4 byte header + 8 byte value
	return 12;
}

/**
 * Returns the attribute, properly encoded and ready for transmission, including the header.
**/
- (NSData *)attributeData
{
	UInt16 attributeLength = [self attributeLength];
	UInt16 valueLength = attributeLength - 4;
	
	NSMutableData *result = [NSMutableData dataWithCapacity:attributeLength];
	
	UInt16 type16 = htons(type);
	UInt16 length = htons(valueLength);
	
	[result appendBytes:&type16 length:sizeof(type16)];
	[result appendBytes:&length length:sizeof(length)];
	
	UInt8 ignore = 0;
	[result appendBytes:&ignore length:sizeof(ignore)];
	
	UInt8 family = 0x01;
	[result appendBytes:&family length:sizeof(family)];
	
	if(xorData == nil)
	{
		UInt16 nPort = htons(port);
		[result appendBytes:&nPort length:sizeof(nPort)];
		
		UInt32 nAddr = 0;
		inet_pton(AF_INET, [address UTF8String], &nAddr);
		
		[result appendBytes:&nAddr length:sizeof(nAddr)];
	}
	else
	{
		UInt16 xor16 = [NSNumber extractUInt16FromData:xorData atOffset:0 andConvertFromNetworkOrder:NO];
		UInt32 xor32 = [NSNumber extractUInt32FromData:xorData atOffset:0 andConvertFromNetworkOrder:NO];
		
		UInt16 nPort = htons(port);
		UInt16 xPort = (nPort ^ xor16);
		[result appendBytes:&xPort length:sizeof(xPort)];
		
		UInt32 nAddr = 0;
		inet_pton(AF_INET, [address UTF8String], &nAddr);
		
		UInt32 xAddr = (nAddr ^ xor32);
		[result appendBytes:&xAddr length:sizeof(xAddr)];
	}
		
	return result;
}

- (UInt16)port
{
	return port;
}

- (NSString *)address
{
	return address;
}

- (NSString *)description
{
	NSString *typeStr = nil;
	
	switch(type)
	{
		case STUN_ATTR_MAPPED_ADDRESS     : typeStr = @"Mapped-Address    ";  break;
		case STUN_ATTR_RESPONSE_ADDRESS   : typeStr = @"Response-Address  ";  break;
		case STUN_ATTR_SOURCE_ADDRESS     : typeStr = @"Source-Address    ";  break;
		case STUN_ATTR_CHANGED_ADDRESS    : typeStr = @"Changed-Address   ";  break;
		case STUN_ATTR_REFLECTED_FROM     : typeStr = @"Reflected-From    ";  break;
		case STUN_ATTR_XOR_MAPPED_ADDRESS : typeStr = @"Xor-Mapped-Address";  break;
		default                           : typeStr = @"Unknown           ";  break;
	}
	
	return [NSString stringWithFormat:@"STUNAddressAttribute: %@: %@:%hu", typeStr, address, port];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define FLAG_CHANGE_IP   0x02
#define FLAG_CHANGE_PORT 0x04

@implementation STUNChangeAttribute

/**
 * Attempts to parse the given attribute data. If unsuccessful, returns nil.
 * It is assumed the given StunAttributeType is proper for this type of attribute.
 * It is assumed the given data is the same size as the given length.
 * The data should point to the attribute value. It should not include the already parsed attribute headers.
 * The length is checked to make sure it's the proper size for this type of attribute.
**/
+ (STUNChangeAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data
{
	if(length != 4)
	{
		DDLogWarn(@"STUNChangeAttribute: parseAttribute: length != 4");
		return nil;
	}
	
	UInt32 flags = [NSNumber extractUInt32FromData:data atOffset:0 andConvertFromNetworkOrder:YES];
	
	BOOL changeIP = flags & FLAG_CHANGE_IP;
	BOOL changePort = flags & FLAG_CHANGE_PORT;
	
	STUNChangeAttribute *result = [[STUNChangeAttribute alloc] initWithChangeIP:changeIP changePort:changePort];
	return [result autorelease];
}

- (id)initWithChangeIP:(BOOL)ipFlag changePort:(BOOL)portFlag
{
	if((self = [super init]))
	{
		flags = 0;
		if(ipFlag)   flags |= FLAG_CHANGE_IP;
		if(portFlag) flags |= FLAG_CHANGE_PORT;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (StunAttributeType)type
{
	return STUN_ATTR_CHANGE_REQUEST;
}

/**
 * Returns the length of the entire attribute, including the header.
**/
- (UInt16)attributeLength
{
	// 4 byte header + 4 byte value
	return 8;
}

/**
 * Returns the attribute, properly encoded and ready for transmission, including the header.
**/
- (NSData *)attributeData
{
	UInt16 attributeLength = [self attributeLength];
	UInt16 valueLength = attributeLength - 4;
	
	NSMutableData *result = [NSMutableData dataWithCapacity:attributeLength];
	
	UInt16 type16 = htons(STUN_ATTR_CHANGE_REQUEST);
	UInt16 length = htons(valueLength);
	
	[result appendBytes:&type16 length:sizeof(type16)];
	[result appendBytes:&length length:sizeof(length)];
	
	UInt32 flags32 = htonl(flags);
	[result appendBytes:&flags32 length:sizeof(flags32)];
	
	NSAssert([result length] == 8, @"Incorrect attibute data length");
	
	return result;
}

- (BOOL)changeIP
{
	return flags & FLAG_CHANGE_IP;
}

- (BOOL)changePort
{
	return flags & FLAG_CHANGE_PORT;
}

- (NSString *)description
{
	NSString *typeStr = @"Change-Request    ";
	
	BOOL changeIP = [self changeIP];
	BOOL changePort = [self changePort];
	
	return [NSString stringWithFormat:@"STUNChangeAttribute : %@: IP(%d) Port(%d)", typeStr, changeIP, changePort];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNErrorAttribute

/**
 * Attempts to parse the given attribute data. If unsuccessful, returns nil.
 * It is assumed the given StunAttributeType is proper for this type of attribute.
 * It is assumed the given data is the same size as the given length.
 * The data should point to the attribute value. It should not include the already parsed attribute headers.
 * The length is checked to make sure it's the proper size for this type of attribute.
**/
+ (STUNErrorAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data
{
	if(length < 4)
	{
		DDLogWarn(@"STUNErrorAttribute: parseAttribute: length < 4");
		return nil;
	}
	
	UInt8 class = [NSNumber extractUInt8FromData:data atOffset:2];
	
	if(class < 1 || class > 6)
	{
		DDLogWarn(@"STUNErrorAttribute: parseAttribute: parsed class is incorrect: %hu", (UInt16)class);
		return nil;
	}
	
	UInt8 order = [NSNumber extractUInt8FromData:data atOffset:3];
	
	if(order > 99)
	{
		DDLogWarn(@"STUNErrorAttribute: parseAttribute: parsed order is incorrect: %hu", (UInt16)order);
		return nil;
	}
	
	unsigned errorCode = (class * 100) + order;
	
	NSString *reasonPhrase = nil;
	if(length > 4)
	{
		void *pBytes = (void *)([data bytes] + 4);
		unsigned sublength = length - 4;
		NSData *subdata = [NSData dataWithBytesNoCopy:pBytes length:sublength freeWhenDone:NO];
		
		reasonPhrase = [[[NSString alloc] initWithData:subdata encoding:NSUTF8StringEncoding] autorelease];
	}
	
	STUNErrorAttribute *result = [[STUNErrorAttribute alloc] initWithErrorCode:errorCode reasonPhrase:reasonPhrase];
	return [result autorelease];
}

- (id)initWithErrorCode:(unsigned)ec reasonPhrase:(NSString *)rp
{
	if((self = [super init]))
	{
		errorCode = ec;
		reasonPhrase = [rp copy];
	}
	return self;
}

- (void)dealloc
{
	[reasonPhrase release];
	[super dealloc];
}

- (StunAttributeType)type
{
	return STUN_ATTR_ERROR_CODE;
}

/**
 * Returns the length of the entire attribute, including the header.
**/
- (UInt16)attributeLength
{
	// 4 byte header + 4 byte error code + variable length reason phrase
	// The variable length reason phrase needs to be a multiple of 4
	unsigned exactLength = [reasonPhrase lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	
	unsigned leftOver = exactLength % 4;
	
	if(leftOver == 0)
		return 4 + 4 + exactLength;
	else
		return 4 + 4 + exactLength + (4 - leftOver);
}

/**
 * Returns the reason phrase, encoded in UTF8 format, and padded to be a multiple of 4 bytes.
 * Null byte padding is added at the end as needed.
**/
- (NSData *)reasonData
{
	if(reasonPhrase == nil) return nil;
	
	NSData *reasonData = [reasonPhrase dataUsingEncoding:NSUTF8StringEncoding];
	
	unsigned exactLength = [reasonData length];
	unsigned leftOver = exactLength % 4;
	
	if(leftOver == 0)
	{
		return reasonData;
	}
	
	NSMutableData *paddedReasonData = [NSMutableData dataWithCapacity:(exactLength + (4 - leftOver))];
	[paddedReasonData appendData:reasonData];
	
	UInt8 ignore = 0;
	
	[paddedReasonData appendBytes:&ignore length:sizeof(ignore)];
	if(leftOver > 1)
	{
		[paddedReasonData appendBytes:&ignore length:sizeof(ignore)];
	}
	if(leftOver > 2)
	{
		[paddedReasonData appendBytes:&ignore length:sizeof(ignore)];
	}
	
	return paddedReasonData;
}

/**
 * Returns the attribute, properly encoded and ready for transmission, including the header.
**/
- (NSData *)attributeData
{
	NSData *reasonData = [self reasonData];
	
	UInt16 valueLength = 4 + [reasonData length];
	UInt16 attributeLength = 4 + valueLength;
	
	NSMutableData *result = [NSMutableData dataWithCapacity:attributeLength];
	
	UInt16 type16 = htons(STUN_ATTR_ERROR_CODE);
	UInt16 length = htons(valueLength);
	
	[result appendBytes:&type16 length:sizeof(type16)];
	[result appendBytes:&length length:sizeof(length)];
	
	UInt16 ignore = htons(0);
	[result appendBytes:&ignore length:sizeof(ignore)];
	
	UInt8 class = htons(errorCode / 100);
	UInt8 order = htons(errorCode % 100);
	
	[result appendBytes:&class length:sizeof(class)];
	[result appendBytes:&order length:sizeof(order)];
	
	[result appendData:reasonData];
	
	return result;
}

- (unsigned)errorCode
{
	return errorCode;
}

- (NSString *)reasonPhrase
{
	return reasonPhrase;
}

- (NSString *)description
{
	NSString *typeStr = @"Error-Code        ";
	
	return [NSString stringWithFormat:@"STUNErrorAttribute  : %@: %u - %@", typeStr, errorCode, reasonPhrase];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNStringAttribute

/**
 * Attempts to parse the given attribute data. If unsuccessful, returns nil.
 * It is assumed the given StunAttributeType is proper for this type of attribute.
 * It is assumed the given data is the same size as the given length.
 * The data should point to the attribute value. It should not include the already parsed attribute headers.
 * The length is checked to make sure it's the proper size for this type of attribute.
**/
+ (STUNStringAttribute *)parseAttributeWithType:(StunAttributeType)type length:(unsigned)length value:(NSData *)data
{
	if(length < 4)
	{
		DDLogWarn(@"STUNStringAttribute: parseAttribute: length < 4");
		return nil;
	}
		
	NSString *str = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	
	STUNStringAttribute *result = [[STUNStringAttribute alloc] initWithType:type string:str];
	return [result autorelease];
}

- (id)initWithType:(StunAttributeType)typeParam string:(NSString *)strParam
{
	if((self = [super init]))
	{
		type = typeParam;
		str = [strParam copy];
	}
	return self;
}

- (void)dealloc
{
	[str release];
	[super dealloc];
}

- (StunAttributeType)type
{
	return type;
}

/**
 * Returns the length of the entire attribute, including the header.
**/
- (UInt16)attributeLength
{
	// 4 byte header + variable length string
	// The variable length string needs to be a multiple of 4
	unsigned exactLength = [str lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	
	unsigned leftOver = exactLength % 4;
	
	if(leftOver == 0)
		return 4 + exactLength;
	else
		return 4 + exactLength + (4 - leftOver);
}

/**
 * Returns the string, encoded in UTF8 format, and padded to be a multiple of 4 bytes.
 * Null byte padding is added at the end as needed.
**/
- (NSData *)stringData
{
	if(str == nil) return nil;
	
	NSData *strData = [str dataUsingEncoding:NSUTF8StringEncoding];
	
	unsigned exactLength = [strData length];
	unsigned leftOver = exactLength % 4;
	
	if(leftOver == 0)
	{
		return strData;
	}
	
	NSMutableData *paddedStrData = [NSMutableData dataWithCapacity:(exactLength + (4 - leftOver))];
	[paddedStrData appendData:strData];
	
	UInt8 ignore = 0;
	
	[paddedStrData appendBytes:&ignore length:sizeof(ignore)];
	if(leftOver > 1)
	{
		[paddedStrData appendBytes:&ignore length:sizeof(ignore)];
	}
	if(leftOver > 2)
	{
		[paddedStrData appendBytes:&ignore length:sizeof(ignore)];
	}
	
	return paddedStrData;
}

/**
 * Returns the attribute, properly encoded and ready for transmission, including the header.
**/
- (NSData *)attributeData
{
	NSData *strData = [self stringData];
	
	UInt16 valueLength = [strData length];
	UInt16 attributeLength = valueLength + 4;
	
	NSMutableData *result = [NSMutableData dataWithCapacity:attributeLength];
	
	UInt16 type16 = htons(type);
	UInt16 length = htons(valueLength);
	
	[result appendBytes:&type16 length:sizeof(type16)];
	[result appendBytes:&length length:sizeof(length)];
	
	[result appendData:strData];
	
	return result;
}

- (NSString *)stringValue
{
	return str;
}

- (NSString *)description
{
	NSString *typeStr = nil;
	
	switch(type)
	{
		case STUN_ATTR_USERNAME : typeStr = @"Username          ";  break;
		case STUN_ATTR_PASSWORD : typeStr = @"Password          ";  break;
		default                 : typeStr = @"Unknown           ";  break;
	}
	
	return [NSString stringWithFormat:@"STUNStringAttribute : %@: %@", typeStr, str];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNPortPredictionLogger

- (id)initWithLocalPort:(UInt16)port
{
	if((self = [super init]))
	{
		localPort = port;
		reportedPort1 = 0;
		reportedPort2 = 0;
		reportedPort3 = 0;
		reportedPort4 = 0;
		predictedPort = 0;
		predictedPortRange = NSMakeRange(0, 0);
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (UInt16)localPort {
	return localPort;
}

- (UInt16)reportedPort1 {
	return reportedPort1;
}
- (void)setReportedPort1:(UInt16)port {
	reportedPort1 = port;
}

- (UInt16)reportedPort2 {
	return reportedPort2;
}
- (void)setReportedPort2:(UInt16)port {
	reportedPort2 = port;
}

- (UInt16)reportedPort3 {
	return reportedPort3;
}
- (void)setReportedPort3:(UInt16)port {
	reportedPort3 = port;
}

- (UInt16)reportedPort4 {
	return reportedPort4;
}
- (void)setReportedPort4:(UInt16)port {
	reportedPort4 = port;
}

- (UInt16)predictedPort {
	return predictedPort;
}
- (void)setPredictedPort:(UInt16)port {
	predictedPort = port;
}

- (NSRange)predictedPortRange {
	return predictedPortRange;
}
- (void)setPredictedPortRange:(NSRange)portRange {
	predictedPortRange = portRange;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation STUNLogger

static NSString *systemVersion;

+ (NSString *)machineUUID
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:STUNT_UUID];
}

+ (NSString *)systemVersion
{
	if(!systemVersion)
	{
		NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
		
		systemVersion = [[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"];
		[systemVersion retain];
	}
	return systemVersion;
}

- (id)initWithSTUNUUID:(NSString *)uuid version:(NSString *)version
{
	if((self = [super init]))
	{
		stunUUID = [uuid copy];
		stunVersion = [version copy];
		
		xorNeeded = NO;
		
		traversalAlgorithm = TRAVERSAL_ALGORITHM_STD;
		
		portPredictions = [[NSMutableArray alloc] initWithCapacity:4];
		
		duration = 0;
		
		success = NO;
		cycle = 0;
		
		readValidation = STUN_VALIDATION_NONE;
		writeValidation = STUN_VALIDATION_NONE;
		
		trace = [[NSMutableString alloc] initWithCapacity:150];
	}
	return self;
}

- (void)dealloc
{
	[stunUUID release];
	[stunVersion release];
	[routerManufacturer release];
	[routerMapping release];
	[routerFiltering release];
	[portPredictions release];
	[failureReason release];
	[trace release];
	[super dealloc];
}

- (void)setRouterManufacturer:(NSString *)manufacturer
{
	if(![routerManufacturer isEqual:manufacturer])
	{
		[routerManufacturer release];
		routerManufacturer = [manufacturer copy];
	}
}

- (void)setRouterMapping:(NSString *)mapping
{
	if(![routerMapping isEqualToString:mapping])
	{
		[routerMapping release];
		routerMapping = [mapping copy];
	}
}

- (void)setRouterFiltering:(NSString *)filtering
{
	if(![routerFiltering isEqualToString:filtering])
	{
		[routerFiltering release];
		routerFiltering = [filtering copy];
	}
}

- (void)setXorNeeded:(BOOL)flag
{
	xorNeeded = flag;
}

- (void)setTraversalAlgorithm:(TraversalAlgorithm)talg
{
	traversalAlgorithm = talg;
}

- (void)addPortPredictionLogger:(STUNPortPredictionLogger *)ppLogger
{
	[portPredictions addObject:ppLogger];
}

- (void)setDuration:(NSTimeInterval)total {
	duration = total;
}

- (void)setSuccess:(BOOL)flag {
	success = flag;
}

- (void)setSuccessCycle:(int)successCycle {
	cycle = successCycle;
}

- (void)setReadValidation:(BOOL)flag {
	readValidation = flag ? STUN_VALIDATION_SUCCESS : STUN_VALIDATION_FAILURE;
}

- (void)setWriteValidation:(BOOL)flag {
	writeValidation = flag ? STUN_VALIDATION_SUCCESS : STUN_VALIDATION_FAILURE;
}

- (void)setFailureReason:(NSString *)reason
{
	if(![failureReason isEqualToString:reason])
	{
		[failureReason release];
		failureReason = [reason copy];
	}
}

- (void)addTraceMethod:(NSString *)method
{
	[trace appendFormat:@"[%@]", method];
}

- (void)addTraceMessage:(NSString *)message, ...
{
	va_list arguments;
	va_start(arguments, message);
	
	NSString *msg = [[NSString alloc] initWithFormat:message arguments:arguments];
	
	[trace appendFormat:@"(%@)", msg];
	[msg release];
}

- (NSData *)postData
{
	NSMutableString *post = [NSMutableString stringWithCapacity:250];
	
	NSString *machineUUID = [[self class] machineUUID];
	
	NSString *osVersion = [[self class] systemVersion];
	
	NSString *versionNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *buildNumber   = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	
	NSString *mojoVersion = [NSString stringWithFormat:@"%@ (%@)", versionNumber, buildNumber];
	
	[post appendFormat:@"computerUUID=%@&", [NSURL urlEncodeValue:machineUUID]];
	[post appendFormat:@"mojoVersion=%@&", [NSURL urlEncodeValue:mojoVersion]];
	[post appendFormat:@"stunUUID=%@&", [NSURL urlEncodeValue:stunUUID]];
	[post appendFormat:@"stunVersion=%@&", [NSURL urlEncodeValue:stunVersion]];
	[post appendFormat:@"osVersion=%@&", [NSURL urlEncodeValue:osVersion]];
	
	if(routerManufacturer)
	{
		[post appendFormat:@"routerManufacturer=%@&", [NSURL urlEncodeValue:routerManufacturer]];
	}
	
	if(routerMapping)
	{
		[post appendFormat:@"routerMapping=%@&", [NSURL urlEncodeValue:routerMapping]];
	}
	if(routerFiltering)
	{
		[post appendFormat:@"routerFiltering=%@&", [NSURL urlEncodeValue:routerFiltering]];
	}
	
	[post appendFormat:@"xor=%d&", xorNeeded];
	
	[post appendFormat:@"traversalAlgorithm=%i&", traversalAlgorithm];
	
	NSUInteger i;
	for(i = 0; i < [portPredictions count]; i++)
	{
		STUNPortPredictionLogger *ppLogger = [portPredictions objectAtIndex:i];
		
		[post appendFormat:@"pp%i_localPort=%hu&",         i, [ppLogger localPort]];
		[post appendFormat:@"pp%i_reportedPort1=%hu&",     i, [ppLogger reportedPort1]];
		[post appendFormat:@"pp%i_reportedPort2=%hu&",     i, [ppLogger reportedPort2]];
		[post appendFormat:@"pp%i_reportedPort3=%hu&",     i, [ppLogger reportedPort3]];
		[post appendFormat:@"pp%i_reportedPort4=%hu&",     i, [ppLogger reportedPort4]];
		[post appendFormat:@"pp%i_predictedPort=%hu&",     i, [ppLogger predictedPort]];
		
		NSString *predictedPortRangeStr = NSStringFromRange([ppLogger predictedPortRange]);
		[post appendFormat:@"pp%i_predictedPortRange=%@&", i, [NSURL urlEncodeValue:predictedPortRangeStr]];
	}
	
	[post appendFormat:@"duration=%f&", duration];
	
	[post appendFormat:@"success=%d&", success];
	[post appendFormat:@"successCycle=%i&", cycle];
	
	[post appendFormat:@"readValidation=%i&", readValidation];
	[post appendFormat:@"writeValidation=%i&", writeValidation];
	
	if(failureReason)
	{
		[post appendFormat:@"failureReason=%@&", [NSURL urlEncodeValue:failureReason]];
	}
	
	if([trace length] > 0)
	{
		[post appendFormat:@"trace=%@&", [NSURL urlEncodeValue:trace]];
	}
	
	return [post dataUsingEncoding:NSUTF8StringEncoding];
}

@end

