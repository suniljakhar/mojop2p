#import <Foundation/Foundation.h>
#import "MojoXMPP.h"


@interface MojoXMPPClient : XMPPClient
{
	NSMutableDictionary *txtRecord;
	
	NSMutableArray *turnConnections;
	NSMutableArray *stunConnections;
	NSMutableArray *stuntConnections;
}

+ (MojoXMPPClient *)sharedInstance;

- (void)start;
- (void)stop;

- (int)connectionState;

- (void)goOnline;
- (void)goOffline;

- (NSArray *)sortedUsersByName;
- (NSArray *)sortedUsersByAvailabilityName;

- (NSArray *)sortedAvailableUsersByName;
- (NSArray *)sortedUnavailableUsersByName;

- (NSArray *)unsortedUsers;
- (NSArray *)unsortedAvailableUsers;
- (NSArray *)unsortedUnavailableUsers;

- (NSArray *)unsortedUserAndMojoResources;
- (NSArray *)sortedUserAndMojoResources;

- (BOOL)isLibraryAvailable:(NSString *)libID;
- (XMPPUserAndMojoResource *)userAndMojoResourceForLibraryID:(NSString *)libID;

- (XMPPUser *)userForRosterOrder:(NSInteger)index;
- (NSUInteger)rosterOrderForUser:(XMPPUser *)user;

- (void)setITunesLibraryID:(NSString *)libID numberOfSongs:(int)numSongs;
- (void)updateShareName;
- (void)updateRequiresPassword;
- (void)updateRequiresTLS;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (MojoXMPPClientDelegate)

- (void)xmppClientDidGoOnline:(XMPPClient *)sender;
- (void)xmppClientDidGoOffline:(XMPPClient *)sender;

@end
