#import "BonjourUtilities.h"
#import "MojoDefinitions.h"


@implementation BonjourUtilities

/**
 * Extracts the libraryID from the cryptic TXTRecordData.
 * Returns nil if the data is nil, or a record of the libraryID doesn't exist.
**/
+ (NSString *)libraryIDForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk;
	if([BonjourUtilities versionForTXTRecordData:txtRecordData] == 2)
		junk = [dict objectForKey:TXTRCD2_LIBRARY_ID];
	else
		junk = [dict objectForKey:TXTRCD1_LIBRARY_ID];
	
	return [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
}

/**
 * Extracts the share name from the cryptic TXTRecordData.
 * Returns nil if the data is nil, or a record of the share name doesn't exist.
**/
+ (NSString *)shareNameForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk;
	if([BonjourUtilities versionForTXTRecordData:txtRecordData] == 2)
		junk = [dict objectForKey:TXTRCD2_SHARE_NAME];
	else
		junk = [dict objectForKey:TXTRCD1_SHARE_NAME];
	
	return [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
}

/**
 * Extracts the zlib support status from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns NO.
**/
+ (BOOL)zlibSupportForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_ZLIB_SUPPORT];
	
	if(junk == nil) return NO;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return ([temp intValue] != 0);
}

/**
 * Extracts the gzip support status from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns NO.
**/
+ (BOOL)gzipSupportForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_GZIP_SUPPORT];
	
	if(junk == nil) return NO;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return ([temp intValue] != 0);
}

/**
 * Extracts the password protection status from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns NO.
**/
+ (BOOL)requiresPasswordForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_REQUIRES_PASSWORD];
	
	if(junk == nil) return NO;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return ([temp intValue] != 0);
}

/**
 * Extracts the secure connection status from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns NO.
**/
+ (BOOL)requiresTLSForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_REQUIRES_TLS];
	
	if(junk == nil) return NO;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return ([temp intValue] != 0);
}

+ (BOOL)stuntSupportForTXTRecordData:(NSData *)txtRecordData
{
	return ([self stuntVersionForTXTRecordData:txtRecordData] > 0.0f);
}

+ (BOOL)stunSupportForTXTRecordData:(NSData *)txtRecordData
{
	return ([self stunVersionForTXTRecordData:txtRecordData] > 0.0f);
}

+ (float)stuntVersionForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_STUNT_VERSION];
	
	if(junk == nil) return 1.0f; // Yes, should be 1.0
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	float result = [temp floatValue];
	
	// Note: STUNT support is mandatory in all Mojo clients, so we can assume it's at least version 1.0.
	// This check is required because we didn't always include the stunt version in the txt record.
	
	if(result > 0.0f)
		return result;
	else
		return 1.0f;
}

+ (float)stunVersionForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_STUN_VERSION];
	
	if(junk == nil) return 0.0f;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return [temp floatValue];
}

/**
 * Extracts the zlib support status from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns 0.
**/
+ (int)numSongsForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk;
	if([BonjourUtilities versionForTXTRecordData:txtRecordData] == 2)
		junk = [dict objectForKey:TXTRCD2_NUM_SONGS];
	else
		junk = [dict objectForKey:TXTRCD1_NUM_SONGS];
	
	if(junk == nil) return 0;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return [temp intValue];
}

/**
 * Extracts the txt record version number from the cryptic TXTRecordData.
 * If the data is nil, or the corresponding record doesn't exist, this method returns 0.
**/
+ (int)versionForTXTRecordData:(NSData *)txtRecordData
{
	NSDictionary *dict = nil;
	if(txtRecordData)
		dict = [NSNetService dictionaryFromTXTRecordData:txtRecordData];
	
	NSData *junk = [dict objectForKey:TXTRCD_VERSION];
	
	if(junk == nil) return 0;
	
	NSString *temp = [[[NSString alloc] initWithData:junk encoding:NSUTF8StringEncoding] autorelease];
	return [temp intValue];
}

@end
