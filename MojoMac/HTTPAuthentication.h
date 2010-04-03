#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
// Note: You may need to add the CFNetwork Framework to your project
#import <CFNetwork/CFNetwork.h>
#endif

/**
 * Abstract Superclass of HTTPAuthenticationRequest and HTTPAuthenticationResponse
**/
@interface HTTPAuthentication : NSObject
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface HTTPAuthenticationRequest : HTTPAuthentication
{
	BOOL isBasic;
	BOOL isDigest;
	
	NSString *base64Credentials;
	
	NSString *username;
	NSString *realm;
	NSString *nonce;
	NSString *uri;
	NSString *qop;
	NSString *nc;
	NSString *cnonce;
	NSString *response;
}
- (id)initWithRequest:(CFHTTPMessageRef)request;

- (BOOL)isBasic;
- (BOOL)isDigest;

// Basic
- (NSString *)base64Credentials;

// Digest
- (NSString *)username;
- (NSString *)realm;
- (NSString *)nonce;
- (NSString *)uri;
- (NSString *)qop;
- (NSString *)nc;
- (NSString *)cnonce;
- (NSString *)response;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface HTTPAuthenticationResponse : HTTPAuthentication
{
	BOOL isBasic;
	BOOL isDigest;
	
	NSString *realm;
	NSString *nonce;
	NSString *qop;
	NSString *cnonce;
	
	uint nc;
}
- (id)initWithResponse:(CFHTTPMessageRef)response;

- (BOOL)isBasic;
- (BOOL)isDigest;

- (NSString *)realm;
- (NSString *)nonce;
- (NSString *)qop;
- (NSString *)nc;
- (NSString *)cnonce;

- (void)incrementNC;

@end
