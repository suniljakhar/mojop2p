#import <Foundation/Foundation.h>
#import "TigerSupport.h"

@class XMPPIQ;
@class XMPPJID;
@class XMPPClient;
@class AsyncSocket;


@interface TURNSocket : NSObject
{
	int state;
	BOOL isClient;
	
	XMPPJID *jid;
	NSString *uuid;
	
	id delegate;
	
	NSString *discoUUID;
	NSTimer *discoTimer;
	
	NSArray *proxyCandidates;
	NSUInteger proxyCandidateIndex;
	
	NSMutableArray *candidateJIDs;
	NSUInteger candidateJIDIndex;
	
	NSMutableArray *streamhosts;
	NSUInteger streamhostIndex;
	
	XMPPJID *proxyJID;
	NSString *proxyHost;
	UInt16 proxyPort;
	
	AsyncSocket *asyncSocket;
	
	NSString *targetPublicKeyHex;
	
	NSDate *startTime, *finishTime;
}

+ (BOOL)isNewStartTurnRequest:(XMPPIQ *)iq;

- (id)initWithJID:(XMPPJID *)jid;
- (id)initWithTurnRequest:(XMPPIQ *)iq;

- (void)start:(id)delegate;

- (BOOL)isClient;

- (void)abort;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSObject (TURNSocketDelegate)

- (void)turnSocket:(TURNSocket *)sender didSucceed:(AsyncSocket *)socket;

- (void)turnSocketDidFail:(TURNSocket *)sender;

@end