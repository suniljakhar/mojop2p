#import <Foundation/Foundation.h>
#import "TigerSupport.h"

@class   AsyncSocket;


@interface HTTPClient : NSObject
{
	AsyncSocket *asyncSocket;
	NSURL *currentURL;
	
	NSString *filePath;
	NSFileHandle *file;
	
	id delegate;
	
	BOOL isProcessingRequestOrResponse;
	
	CFHTTPMessageRef request;
	CFHTTPMessageRef response;
	
	UInt64 fileSizeInBytes;
	UInt64 totalBytesReceived;
	UInt64 progressOfCurrentRead;
	
	BOOL usingChunkedTransfer;
	uint chunkedTransferStage;
	
	UInt64 chunkSizeInBytes;
	UInt64 totalChunkReceived;
	
	CFHTTPAuthenticationRef auth;
	NSString *username;
	NSString *password;
	BOOL haveUsedExistingCredentials;
}

- (id)init;
- (id)initWithSocket:(AsyncSocket *)socket baseURL:(NSURL *)baseURL;

- (id)delegate;
- (void)setDelegate:(id)newDelegate;

- (BOOL)isConnected;

- (void)setSocket:(AsyncSocket *)socket baseURL:(NSURL *)baseURL;

- (void)downloadURL:(NSURL *)url toFile:(NSString *)filePath;

- (NSURL *)url;
- (NSString *)filePath;

- (NSString *)username;
- (NSString *)password;
- (void)setUsername:(NSString *)username password:(NSString *)password;

- (void)abort;

- (UInt64)fileSizeInBytes;
- (UInt64)totalBytesReceived;

- (double)progress;

- (NSString *)authenticationRealm;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (HTTPClientDelegateMethods)

- (void)httpClientDownloadDidBegin:(HTTPClient *)httpClient;

- (void)httpClient:(HTTPClient *)httpClient didReceiveDataOfLength:(unsigned)length;

- (void)httpClient:(HTTPClient *)httpClient downloadDidFinish:(NSString *)filePath;

- (void)httpClient:(HTTPClient *)httpClient didFailWithError:(NSError *)error;
- (void)httpClient:(HTTPClient *)httpClient didFailWithStatusCode:(UInt32)statusCode;
- (void)httpClient:(HTTPClient *)httpClient didFailWithAuthenticationChallenge:(CFHTTPAuthenticationRef)auth;

@end
