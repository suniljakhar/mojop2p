/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@class AsyncUdpSocket;


@interface PseudoTcp : NSObject
{
	AsyncUdpSocket *udpSocket;
	id delegate;
	
	Byte flags;
	Byte state;
	
	NSMutableArray *recvBuffer;
	NSMutableArray *recvOutOfOrderBuffer;
	UInt32 recvBufferOffset;
	UInt32 recvBufferSize;
	UInt32 recvSequence;
	
	NSTimer *ackTimer;
	UInt32 unackedPackets;
	
	NSMutableArray *sendBuffer;
	UInt32 sendBufferOffset;
	UInt32 sendBufferSize;
	UInt32 sendSequence;
	UInt32 sendWindow;
	
	NSMutableArray *retransmissionQueue;
	UInt32 retransmissionQueueSize;
	UInt32 retransmissionQueueEffectiveSize;
	UInt32 lastAck;
	UInt16 lastAckCount;
	
	BOOL receiverSupportsSack;
	
	NSTimer *retransmissionTimer;
	
	// RFC 2581
	UInt32 cwnd;      // Congestion window
	UInt32 ssthresh;  // Slow start threshold size
	
	// RFC 2988
	NSTimeInterval srtt;    // Smoothed round trip time
	NSTimeInterval rttvar;  // Rtt variance
	NSTimeInterval rto;     // Retransmission timeout
	
	// RFC 3782
	UInt32 recover;
	
	NSTimer *persistTimer;  // Empty window probing
	
	NSTimer *keepAliveTimer;
	NSDate *lastPacketTime;
}

- (id)initWithUdpSocket:(AsyncUdpSocket *)udpSock;

- (AsyncUdpSocket *)udpSocket;

- (id)delegate;
- (void)setDelegate:(id)delegate;

- (void)activeOpen;
- (void)passiveOpen;

- (BOOL)canAcceptBytes;
- (UInt32)writeData:(NSData *)data atOffset:(UInt32)offset withMaxLength:(UInt32)length;

- (BOOL)hasBytesAvailable;
- (UInt32)read:(UInt8 *)buffer maxLength:(UInt32)length;

- (void)closeAfterWriting;

- (void)setRunLoopModes:(NSArray *)modes;
- (NSArray *)runLoopModes;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface PseudoTcp (PsuedoTcpDelegate)

- (void)onPseudoTcpDidOpen:(PseudoTcp *)sock;

- (void)onPseudoTcpHasBytesAvailable:(PseudoTcp *)sock;

- (void)onPseudoTcpCanAcceptBytes:(PseudoTcp *)sock;

- (void)onPseudoTcp:(PseudoTcp *)sock willCloseWithError:(NSError *)err;

- (void)onPseudoTcpDidClose:(PseudoTcp *)sock;

@end
