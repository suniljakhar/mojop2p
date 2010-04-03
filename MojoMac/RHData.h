#import <Foundation/Foundation.h>


@interface NSData (RHData)

// zlib compression utilities
- (NSData *)zlibInflate;
- (NSData *)zlibDeflate;
- (NSData *)zlibDeflateWithCompressionLevel:(int)level;

// gzip compression utilities
- (NSData *)gzipInflate;
- (NSData *)gzipDeflate;
- (NSData *)gzipDeflateWithCompressionLevel:(int)level;

@end
