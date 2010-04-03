#import <Foundation/Foundation.h>
#import "TigerSupport.h"
#import "XMPP.h"

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
#define NSStringCompareOptions unsigned
#endif


@interface XMPPUser (MojoAdditions)

- (NSString *)mojoDisplayName;
- (NSString *)mojoDisplayName:(XMPPResource *)resource;

- (BOOL)hasMojoResource;
- (XMPPResource *)primaryMojoResource;

- (XMPPResource *)resourceForLibraryID:(NSString *)libID;

- (NSArray *)sortedMojoResources;
- (NSArray *)unsortedMojoResources;

- (NSComparisonResult)compareByMojoName:(XMPPUser *)another;
- (NSComparisonResult)compareByMojoName:(XMPPUser *)another options:(NSStringCompareOptions)mask;

- (NSComparisonResult)compareByMojoAvailabilityName:(XMPPUser *)another;
- (NSComparisonResult)compareByMojoAvailabilityName:(XMPPUser *)another options:(NSStringCompareOptions)mask;

- (NSInteger)strictRosterOrder;
- (NSComparisonResult)strictRosterOrderCompare:(XMPPUser *)aUser;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface XMPPResource (MojoAdditions)

- (BOOL)isMojoResource;

- (NSString *)libraryID;
- (NSString *)shareName;
- (BOOL)zlibSupport;
- (BOOL)gzipSupport;
- (BOOL)requiresPassword;
- (BOOL)requiresTLS;
- (BOOL)stuntSupport;
- (BOOL)stunSupport;
- (BOOL)searchSupport;
- (float)stuntVersion;
- (float)stunVersion;
- (float)searchVersion;
- (int)numSongs;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface XMPPUserAndMojoResource : NSObject <NSCoding>
{
	XMPPUser *user;
	XMPPResource *resource;
}

- (id)initWithUser:(XMPPUser *)user resource:(XMPPResource *)resource;

- (XMPPUser *)user;
- (XMPPResource *)resource;

- (NSString *)displayName;
- (NSString *)mojoDisplayName;

- (NSString *)libraryID;
- (NSString *)shareName;
- (BOOL)zlibSupport;
- (BOOL)gzipSupport;
- (BOOL)requiresPassword;
- (BOOL)requiresTLS;
- (int)numSongs;

- (NSComparisonResult)compare:(XMPPUserAndMojoResource *)another;

@end
