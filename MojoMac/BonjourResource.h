#import <Foundation/Foundation.h>

// This class will post the following notifications (defined in MojoDefinitions.h):
// 
// DidUpdateLocalServiceNotification


@interface BonjourResource : NSObject <NSCoding>
{
	NSNetService *netService;
	NSData *txtRecordData;
	
	NSMutableArray *resolvers;
	
	NSString *nickname;
}

- (id)initWithNetService:(NSNetService *)netService;

- (NSString *)domain;
- (NSString *)type;
- (NSString *)name;

- (NSString *)libraryID;
- (NSString *)shareName;
- (BOOL)zlibSupport;
- (BOOL)gzipSupport;
- (BOOL)requiresPassword;
- (BOOL)requiresTLS;
- (int)numSongs;

- (NSString *)nickname;
- (NSString *)displayName;

- (void)resolveForSender:(id)sender;
- (void)stopResolvingForSender:(id)sender;

- (NSComparisonResult)compareByName:(BonjourResource *)user;
- (NSComparisonResult)compareByName:(BonjourResource *)user options:(unsigned)mask;

- (NSString *)description;
- (NSString *)netServiceDescription;

@end

@interface NSObject (BonjourResourceDelegate)

- (void)bonjourResource:(BonjourResource *)sender didResolveAddresses:(NSArray *)addresses;
- (void)bonjourResource:(BonjourResource *)sender didNotResolve:(NSDictionary *)errorDict;

@end
