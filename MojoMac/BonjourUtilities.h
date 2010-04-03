#import <Foundation/Foundation.h>


@interface BonjourUtilities : NSObject

+ (NSString *)libraryIDForTXTRecordData:(NSData *)txtRecordData;
+ (NSString *)shareNameForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)zlibSupportForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)gzipSupportForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)requiresPasswordForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)requiresTLSForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)stuntSupportForTXTRecordData:(NSData *)txtRecordData;
+ (BOOL)stunSupportForTXTRecordData:(NSData *)txtRecordData;
+ (float)stuntVersionForTXTRecordData:(NSData *)txtRecordData;
+ (float)stunVersionForTXTRecordData:(NSData *)txtRecordData;
+ (int)numSongsForTXTRecordData:(NSData *)txtRecordData;
+ (int)versionForTXTRecordData:(NSData *)txtRecordData;

@end
