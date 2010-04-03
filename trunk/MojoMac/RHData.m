#import "RHData.h"
#import "TigerSupport.h"

#import <zlib.h>


@implementation NSData (RHData)

/**
 * This method remains untested on a PowerPC machine...
**/
+ (NSData *)dataFromHexString:(NSString *)hexStr
{
	if(([hexStr length] % 2) == 1) return nil;
	
	BOOL error = NO;
	
	size_t bufferLength = [hexStr length] / 2;
	UInt8 *buffer = malloc(bufferLength);
	
	unichar c0, c1;
	UInt8 high, low;
	
	NSUInteger i, j;
	for(i = j = 0; i < [hexStr length]; i+=2, j+=1)
	{
		c0 = [hexStr characterAtIndex:i+0];
		c1 = [hexStr characterAtIndex:i+1];
		
		switch(c0)
		{
			case '0' : high =  0;  break;
			case '1' : high =  1;  break;
			case '2' : high =  2;  break;
			case '3' : high =  3;  break;
			case '4' : high =  4;  break;
			case '5' : high =  5;  break;
			case '6' : high =  6;  break;
			case '7' : high =  7;  break;
			case '8' : high =  8;  break;
			case '9' : high =  9;  break;
			case 'A' : 
			case 'a' : high = 10;  break;
			case 'B' : 
			case 'b' : high = 11;  break;
			case 'C' : 
			case 'c' : high = 12;  break;
			case 'D' : 
			case 'd' : high = 13;  break;
			case 'E' : 
			case 'e' : high = 14;  break;
			case 'F' : 
			case 'f' : high = 15;  break;
			default  : high =  0; error = YES; 
		}
		
		switch(c1)
		{
			case '0' : low =  0;  break;
			case '1' : low =  1;  break;
			case '2' : low =  2;  break;
			case '3' : low =  3;  break;
			case '4' : low =  4;  break;
			case '5' : low =  5;  break;
			case '6' : low =  6;  break;
			case '7' : low =  7;  break;
			case '8' : low =  8;  break;
			case '9' : low =  9;  break;
			case 'A' : 
			case 'a' : low = 10;  break;
			case 'B' : 
			case 'b' : low = 11;  break;
			case 'C' : 
			case 'c' : low = 12;  break;
			case 'D' : 
			case 'd' : low = 13;  break;
			case 'E' : 
			case 'e' : low = 14;  break;
			case 'F' : 
			case 'f' : low = 15;  break;
			default  : low =  0; error = YES;
		}
		
		buffer[j] = ((high << 4) | low);
	}
	
	if(error)
	{
		free(buffer);
		return nil;
	}
	else
	{
		return [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:YES];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark zlib:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)zlibInflate
{
	if ([self length] == 0) return self;
	
	unsigned full_length = [self length];
	unsigned half_length = [self length] / 2;
	
	NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];
	BOOL done = NO;
	int status;
	
	z_stream strm;
	strm.next_in = (Bytef *)[self bytes];
	strm.avail_in = [self length];
	strm.total_out = 0;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	
	if (inflateInit(&strm) != Z_OK) return nil;
	while (!done)
	{
		// Make sure we have enough room and reset the lengths.
		if (strm.total_out >= [decompressed length])
			[decompressed increaseLengthBy: half_length];
		strm.next_out = [decompressed mutableBytes] + strm.total_out;
		strm.avail_out = [decompressed length] - strm.total_out;
		
		// Inflate another chunk.
		status = inflate (&strm, Z_SYNC_FLUSH);
		if (status == Z_STREAM_END) done = YES;
		else if (status != Z_OK) break;
	}
	if (inflateEnd (&strm) != Z_OK) return nil;
	
	// Set real length.
	if (done)
	{
		[decompressed setLength: strm.total_out];
		return [NSData dataWithData: decompressed];
	}
	else return nil;
}

- (NSData *)zlibDeflate
{
	return [self zlibDeflateWithCompressionLevel:Z_DEFAULT_COMPRESSION];
}

- (NSData *)zlibDeflateWithCompressionLevel:(int)level
{
	if ([self length] == 0) return self;
	
	// Compresssion levels range from 0 to 9.
	// Common levels are defined:
	// 
	//   Z_NO_COMPRESSION      =  0
	//   Z_BEST_SPEED          =  1
	//   Z_BEST_COMPRESSION    =  9
	//   Z_DEFAULT_COMPRESSION = -1 (currently equivalent to level 6)
	
	if (level < -1 || level > 9) level = Z_DEFAULT_COMPRESSION;
	
	z_stream strm;
	
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.total_out = 0;
	strm.next_in=(Bytef *)[self bytes];
	strm.avail_in = [self length];
	
	if (deflateInit(&strm, level) != Z_OK) return nil;
	
	NSMutableData *compressed = [NSMutableData dataWithLength:16384];  // 16K chunks for expansion
	
	do {
		
		if (strm.total_out >= [compressed length])
			[compressed increaseLengthBy: 16384];
		
		strm.next_out = [compressed mutableBytes] + strm.total_out;
		strm.avail_out = [compressed length] - strm.total_out;
		
		deflate(&strm, Z_FINISH);  
		
	} while (strm.avail_out == 0);
	
	deflateEnd(&strm);
	
	[compressed setLength: strm.total_out];
	return [NSData dataWithData:compressed];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark gzip:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)gzipInflate
{
	if ([self length] == 0) return self;
	
	unsigned full_length = [self length];
	unsigned half_length = [self length] / 2;
	
	NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];
	BOOL done = NO;
	int status;
	
	z_stream strm;
	strm.next_in = (Bytef *)[self bytes];
	strm.avail_in = [self length];
	strm.total_out = 0;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	
	if (inflateInit2(&strm, (15+32)) != Z_OK) return nil;
	while (!done)
	{
		// Make sure we have enough room and reset the lengths.
		if (strm.total_out >= [decompressed length])
			[decompressed increaseLengthBy: half_length];
		strm.next_out = [decompressed mutableBytes] + strm.total_out;
		strm.avail_out = [decompressed length] - strm.total_out;
		
		// Inflate another chunk.
		status = inflate (&strm, Z_SYNC_FLUSH);
		if (status == Z_STREAM_END) done = YES;
		else if (status != Z_OK) break;
	}
	if (inflateEnd (&strm) != Z_OK) return nil;
	
	// Set real length.
	if (done)
	{
		[decompressed setLength: strm.total_out];
		return [NSData dataWithData: decompressed];
	}
	else return nil;
}

- (NSData *)gzipDeflate
{
	return [self gzipDeflateWithCompressionLevel:Z_DEFAULT_COMPRESSION];
}

- (NSData *)gzipDeflateWithCompressionLevel:(int)level
{
	if ([self length] == 0) return self;
	
	// Compresssion levels range from 0 to 9.
	// Common levels are defined:
	// 
	//   Z_NO_COMPRESSION      =  0
	//   Z_BEST_SPEED          =  1
	//   Z_BEST_COMPRESSION    =  9
	//   Z_DEFAULT_COMPRESSION = -1 (currently equivalent to level 6)
	
	if (level < -1 || level > 9) level = Z_DEFAULT_COMPRESSION;
	
	z_stream strm;
	
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.total_out = 0;
	strm.next_in=(Bytef *)[self bytes];
	strm.avail_in = [self length];
	
	if (deflateInit2(&strm, level, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
	
	NSMutableData *compressed = [NSMutableData dataWithLength:16384];  // 16K chunks for expansion
	
	do
	{
		if (strm.total_out >= [compressed length])
			[compressed increaseLengthBy: 16384];
		
		strm.next_out = [compressed mutableBytes] + strm.total_out;
		strm.avail_out = [compressed length] - strm.total_out;
		
		deflate(&strm, Z_FINISH);  
		
	} while (strm.avail_out == 0);
	
	deflateEnd(&strm);
	
	[compressed setLength: strm.total_out];
	return [NSData dataWithData:compressed];
}

@end
