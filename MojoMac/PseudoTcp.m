/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "PseudoTcp.h"
#import "PseudoTcpPacket.h"
#import "AsyncUdpSocket.h"
#import "TigerSupport.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 2
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

// Define the standard TCP states
#define STATE_INIT          0
#define STATE_LISTEN        1
#define STATE_SYN_SENT      2
#define STATE_SYN_RECEIVED  3
#define STATE_ESTABLISHED   4
#define STATE_CLOSED        5

// Define the various timeouts we'll use
#define NO_TIMEOUT          -1
#define ACK_TIMEOUT          0.10
#define KEEP_ALIVE_TIMEOUT  25.00

// Minimum MTU for IP is 576
// Default TCP MTU is 536, which is 576 minus 20 bytes for IP header and minus 20 bytes for TCP header
// We need 20 bytes for IP header, 8 bytes for UDP header, and 12 bytes for TCP header
#define DEFAULT_MTU  536

// Define sizes of our send and receive buffers
#if TARGET_OS_IPHONE
  #define RECV_BUFFER_SIZE  32767
  #define SEND_BUFFER_SIZE  32767
#else
  #define RECV_BUFFER_SIZE  65535
  #define SEND_BUFFER_SIZE  65535
#endif

// Define retransmission timeouts (in seconds)
#define SYN_TIMEOUT   180.0
#define DATA_TIMEOUT  100.0

enum PseudoTcpFlags
{
	kNewDataAvailable  = 1 << 0,   // If set, new data is available and the delegate should be informed
	kConnectionReset   = 1 << 1,   // If set, we've received a reset message from the remote host
	kForbidWrites      = 1 << 2,   // If set, no new writes are allowed
	kRecover           = 1 << 3,   // If set, the recover variable is valid
	kFirstPartial      = 1 << 4,   // If set, a partial ack will indicate the first partial ack received
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface PseudoTcp (PrivateAPI)

// Run Loop
- (void)runLoopAddTimer:(NSTimer *)timer;
- (void)runLoopRemoveTimer:(NSTimer *)timer;

// State
- (UInt32)recvWindow;
- (UInt32)expectedSequence;
- (UInt32)spaceAvailableInSendBuffer;
- (UInt32)sendUnacknowledged;
- (UInt32)sendNext;

// New Reno
- (void)setRecover;
- (void)unsetRecover;
- (BOOL)isFullAck:(UInt32)ack;
- (BOOL)isFirstPartialAck;

// Utilities
- (void)sendPacket:(PseudoTcpPacket *)packet;
- (void)resendPacket:(PseudoTcpPacket *)packet;
- (void)cleanup;

// Handshake
- (void)processOpeningSyn:(PseudoTcpPacket *)synPacket;
- (void)processOpeningSynAck:(PseudoTcpPacket *)synAckPacket;
- (void)processOpeningAck:(PseudoTcpPacket *)ackPacket;

// ACK
- (void)processDataAck:(PseudoTcpPacket *)ackPacket;
- (BOOL)isAckWithinRetransmissionQueue:(UInt32)ack;
- (BOOL)doesAck:(UInt32)ack absolvePacket:(PseudoTcpPacket *)packet;
- (void)scheduleDelayedAck;
- (void)sendAckNow;
- (void)sendSackNow;
- (void)maybeAddAck:(PseudoTcpPacket *)dataPacket;

// Data
- (void)processData:(PseudoTcpPacket *)packet;
- (BOOL)doesPacketFitInRecvWindow:(PseudoTcpPacket *)packet;
- (void)scheduleMaybeSendData;
- (void)maybeSendData;
- (void)resendPacketWithSequence:(UInt32)sequence;
- (void)maybeScheduleEmptyWindowProbe;

// RST
- (void)processRst:(PseudoTcpPacket *)rstPacket;
- (void)maybeSendRst;

@end

// THE RECEIVE BUFFER:
// 
// The receive buffer is an array of received PseudoTcpPacket objects.
// The array is kept sorted according to sequence number, taking wrap-around into account.
// Any out-of-order data that arrives is similarly stored in a seperate array.
// This seperate array only includes packets that would fit in the receive window (taking into
// account the RECV_BUFFER_SIZE), had they not been out-of-order.
// 
// Using arrays instead of NSMutableData takes up less memory in most cases.
// This is because allocating a NSMutableData object of size 64K always takes up 64K,
// but creating an array and limiting its size to 64K of data will often take up much less than 64K.
// This technique also avoids many underlying memcopy's and memmove's.
// 
// The recvBufferSize is the amount of data in the recvBuffer that hasn't been read by the upper-layer.
// The recvBufferOffset is the amount of data, in the first PseudoTcpPacket in the recvBuffer,
// that has been read by the upper-layer.
// The recvSequence is the sequence number of the first byte of data in the first PseudoTcpPacket in the recvBuffer.
// If the recvBuffer is empty, then the recvSequence is the sequence number we're expecting next.
// 
// Using the above three numbers, one can easily determine all needed information.
// For example:
// The next expected sequence number is recvSequnce + recvBufferOffset + recvBufferSize.
// The sequence number of the first byte of unread data by upper-layer is recvSequence + recvBufferOffset.

// SENDING ACK'S AND NOTIFYING THE DELEGATE OF NEW DATA:
// 
// We implement delayed ack's according to the TCP specifications.
// So when we receive a single packet, we schedule a delayed ack, and then notify the delegate of new data.
// After a short period of time, the ack timer will expire, and the delayed ack will be sent.
// If we receive more data before the ack timer expires, we will then send an immediate ack, and postpone
// notifying the delegate until after we know the ack has been sent.
// This way the ack is not delayed by any data processing the delegate may do, and
// we minimize ack delays where they should properly be minimized.
// The delayed ack may also be interrupted if we are sending data, as acks can and will be tacked onto data packets.

// THE SEND BUFFER:
// 
// The send buffer is an array of NSData objects.
// 
// Similarly to the receive buffer, we use arrays instead of NSMutableData to take up less memory.
// In the case of an http client, sending small requests, the benefits are easily seen.
// In the case of an http server, sending large amounts of data, the benefits may be slim memory wise.
// However, the technique will sometimes avoid many memcopy's,
// and the memmove's required to shift the sliding window are not needed.
// 
// The sendBufferSize is the amound of data in the sendBuffer that hasn't been sent.
// The sendBufferOffset is the amount of data, in the first NSData in the sendBuffer, that has already been sent.
// The sendSequence is the sequence number of the first byte of data in the first NSData object in the sendBuffer.
// If the sendBuffer is empty, then the sendSequence is the sequence number of the next byte to go into the sendBuffer.
// 
// As data is sent, it is copied into PseudoTcpPackets, and these packets are placed into the retransmissionQueue.
// The retransmission queue is kept sorted according to sequence number, taking wrap-around into account.
// That is, the oldest packet sent and yet unacknowledged is the first packet in the queue.
// As ack's are received, affected packets from the retransmission queue are removed.
// 
// In most tcp explanations, the send buffer is presented as a sliding window of data.
// The send buffer in these diagrams includes both the data that is waiting to be acknowledged, in addition to
// the data that is waiting to be sent.  In the same way, the conecptual send buffer of PseudoTcp includes both
// the retransmission queue and the send buffer.

// KEEP ALIVE:
// 
// Since UDP is stateless, routers simply look for inactivity in order to remove port mappings.
// Many routers will use activity timeouts as short as 30 seconds.
// So we simply send packets every once in a while if there is no activity on the socket.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation PseudoTcp

/**
 * Returns a random port UInt32 number
**/
+ (UInt32)randomNumber
{
	return (UInt32)arc4random();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithUdpSocket:(AsyncUdpSocket *)udpSock
{
	if(![udpSock isConnected])
	{
		DDLogError(@"PseudoTcp: initWithUdpSocket: udpSocket is not connected!");
		
		[super dealloc];
		return nil;
	}
	
	if((self = [super init]))
	{
		udpSocket = [udpSock retain];
		[udpSocket setDelegate:self];
		[udpSocket setMaxReceiveBufferSize:(PSEUDO_TCP_HEADER_SIZE + DEFAULT_MTU)];
		
		flags = 0;
		state = STATE_INIT;
		
		recvBuffer = [[NSMutableArray alloc] initWithCapacity:30];
		recvOutOfOrderBuffer = [[NSMutableArray alloc] initWithCapacity:10];
		recvBufferOffset = 0;
		recvBufferSize = 0;
		
		unackedPackets = 0;
		
		sendBuffer = [[NSMutableArray alloc] initWithCapacity:30];
		sendBufferOffset = 0;
		sendBufferSize = 0;
		
		sendSequence = [[self class] randomNumber];
		
		retransmissionQueue = [[NSMutableArray alloc] initWithCapacity:15];
		retransmissionQueueSize = 0;
		retransmissionQueueEffectiveSize = 0;
		lastAck = sendSequence;
		lastAckCount = 0;
		
		cwnd = 2 * DEFAULT_MTU; // As per RFC 2581
		ssthresh = 65535;
		
		srtt   = 0.0;
		rttvar = 0.0;
		rto    = 3.0;
		
		recover = sendSequence;
		
		keepAliveTimer = [[NSTimer timerWithTimeInterval:KEEP_ALIVE_TIMEOUT
												  target:self
												selector:@selector(doKeepAliveTimeout:)
												userInfo:nil
												 repeats:NO] retain];
		[self runLoopAddTimer:keepAliveTimer];
		
		lastPacketTime = [[NSDate distantPast] retain];
	}
	return self;
}

- (void)dealloc
{
	DDLogInfo(@"Destroying %@", self);
	
	if([udpSocket delegate] == self)
	{
		[udpSocket setDelegate:nil];
		[udpSocket close];
	}
	[udpSocket release];
	[recvBuffer release];
	[recvOutOfOrderBuffer release];
	[ackTimer invalidate];
	[ackTimer release];
	[sendBuffer release];
	[retransmissionQueue release];
	[retransmissionTimer invalidate];
	[retransmissionTimer release];
	[persistTimer invalidate];
	[persistTimer release];
	[keepAliveTimer invalidate];
	[keepAliveTimer release];
	[lastPacketTime release];
	[NSObject cancelPreviousPerformRequestsWithTarget:delegate selector:@selector(onPseudoTcpDidClose:) object:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)delegate
{
	return delegate;
}

- (void)setDelegate:(id)newDelegate
{
	delegate = newDelegate;
}

- (AsyncUdpSocket *)udpSocket
{
	return udpSocket;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Run Loop
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)runLoopAddTimer:(NSTimer *)timer
{
	CFRunLoopRef runLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	NSArray *runLoopModes = [udpSocket runLoopModes];
	unsigned int i, count = [runLoopModes count];
	for(i = 0; i < count; i++)
	{
		NSString *mode = [runLoopModes objectAtIndex:i];
		CFRunLoopAddTimer(runLoop, (CFRunLoopTimerRef)timer, (CFStringRef)mode);
	}
}

- (void)runLoopRemoveTimer:(NSTimer *)timer
{
	CFRunLoopRef runLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	NSArray *runLoopModes = [udpSocket runLoopModes];
	unsigned int i, count = [runLoopModes count];
	for(i = 0; i < count; i++)
	{
		NSString *mode = [runLoopModes objectAtIndex:i];
		CFRunLoopRemoveTimer(runLoop, (CFRunLoopTimerRef)timer, (CFStringRef)mode);
	}
}

- (void)setRunLoopModes:(NSArray *)modes
{
	[udpSocket setRunLoopModes:modes];
	
	if(ackTimer)
	{
		[self runLoopRemoveTimer:ackTimer];
		[self runLoopAddTimer:ackTimer];
	}
	if(retransmissionTimer)
	{
		[self runLoopRemoveTimer:retransmissionTimer];
		[self runLoopAddTimer:retransmissionTimer];
	}
	if(persistTimer)
	{
		[self runLoopRemoveTimer:persistTimer];
		[self runLoopAddTimer:persistTimer];
	}
	if(keepAliveTimer)
	{
		[self runLoopRemoveTimer:keepAliveTimer];
		[self runLoopAddTimer:keepAliveTimer];
	}
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self performSelector:@selector(maybeSendData) withObject:nil afterDelay:0.0 inModes:modes];
}

- (NSArray *)runLoopModes
{
	return [udpSocket runLoopModes];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection Control
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)activeOpen
{
	if(state == STATE_INIT)
	{
		// Create the opening SYN packet
		PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] init] autorelease];
		[packet setSequence:(sendSequence - 1)];
		[packet setWindow:[self recvWindow]];
		[packet setIsSyn:YES];
		[packet setIsSack:YES];
		
		[self sendPacket:packet];
		
		// Start listening for SYN ACK
		[udpSocket receiveWithTimeout:NO_TIMEOUT tag:0];
		
		// Update state
		state = STATE_SYN_SENT;
	}
}

- (void)passiveOpen
{
	if(state == STATE_INIT)
	{
		// Start listening for an opening SYN packet
		[udpSocket receiveWithTimeout:NO_TIMEOUT tag:0];
		
		// Update state
		state = STATE_LISTEN;
	}
}

- (void)closeAfterWriting
{
	DDLogInfo(@"PseudoTcp: closeAfterWriting");
	
	if(state < STATE_ESTABLISHED)
	{
		// Send a RST message if we've already started communication
		if(state == STATE_SYN_SENT || state == STATE_SYN_RECEIVED)
		{
			[self maybeSendRst];
		}
		
		// The maybeSendRst method might have closed everything down already
		if(state != STATE_CLOSED)
		{
			// Update state
			state = STATE_CLOSED;
			
			// Release TCP resources
			[self cleanup];
			
			// Notify delegate of closed socket
			if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
			{
				[delegate performSelector:@selector(onPseudoTcpDidClose:)
							   withObject:self
							   afterDelay:0.0
								  inModes:[udpSocket runLoopModes]];
			}
		}
	}
	else if(state == STATE_ESTABLISHED)
	{
		// Forbid any more writes
		flags |= kForbidWrites;
		
		// Wait till all queued data has been sent and acked, then send RST
		[self maybeSendRst];
		
		// The maybeSendRst method will close everything down if all data has been sent and acked.
		// Otherwise, we continue to call it from now on everytime we receive a new ack.
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Sending and Receiving
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns whether or not the pseudo socket can accept any bytes.
 * If this method returns YES, one should be able to call writeData:atOffset:withMaxLength:
 * and have it return a positive number.
**/
- (BOOL)canAcceptBytes
{
	if(state != STATE_ESTABLISHED) return NO;
	if(flags & kForbidWrites) return NO;
	
	// Remember: Although the retransmissionQueue and sendBuffer are separate,
	// they both combine to make up the conceptual send buffer.
	
	// Technically, this is the answer:
	// return (retransmissionQueueSize + sendBufferSize) < SEND_BUFFER_SIZE;
	
	// However, if we consider how this class is used by the PseudoAsyncSocket class, this is not the best answer.
	// Because the PseudoAsyncSocket, after writing a large chunk of data, will immediately fetch the
	// next chunk of data, and then immediately ask us if we can accept bytes.
	// The technical answer above would result in many YES answers, when the space available in the buffer is small.
	// This will result in many small writes to our buffer.
	// For better performance, we only answer YES when we can accept a larger chunk of data.
	
	return [self spaceAvailableInSendBuffer] > (SEND_BUFFER_SIZE / 4);
}

/**
 * Writes as much data as possible to the internal send buffer.
 * The amount written will be limited by the available space in the internal send buffer.
 * The amount written will not necessarily be as much as the given max length.
 * It will be the minimum of:
 * - The amount of space available in the send buffer
 * - The actual size of the given data
 * - The given max length
**/
- (UInt32)writeData:(NSData *)data atOffset:(UInt32)offset withMaxLength:(UInt32)maxLength
{
	if(![self canAcceptBytes]) return 0;
	if(data == nil || [data length] == 0) return 0;
	
	DDLogVerbose(@"PseudoTcp: writeData:(length=%u) atOffset:%u withMaxLength:%u",
				 (unsigned)[data length], offset, maxLength);
	
	// Determine how much we can actually read.
	// This is the minimum of:
	// - How much space we have available in the send buffer
	// - How much data we're allowed to read
	// - How much data was passed
	UInt32 dataAvailable = [data length] - offset;
	UInt32 maxReadableLength = MIN([self spaceAvailableInSendBuffer], MIN(maxLength, dataAvailable));
	
	// If they pass NSMutableData, we're forced to make a copy.
	// If they pass NSData, and we can only accept part of it, we're forced to make a copy.
	// If they pass NSData, and we can accept the entire thing, we can simply retain it and avoid making a copy.
	// 
	// Wait - This trick doesn't work!
	// 
	// We had previously used it and it caused horrible crashes.
	// The problem occurred when optimizations were made higher up, and data was passed that was
	// created via dataWithBytesNoCopy. In this case, the data appears immutable, but a retain/copy of the
	// object does not prevent the original data from being deallocated.
	// The only solution to this problem outside of copying the bytes is a hack, requiring knowledge
	// of the underlying _CFData struct, and it's _bytesDeallocator member.
	
	NSAssert2(offset < [data length], @"offset(%u) >= data(length=%u)", offset, (unsigned)[data length]);
	
	const void *subData = [data bytes] + offset;
	NSData *fragment = [NSData dataWithBytes:subData length:maxReadableLength];
	
	[sendBuffer addObject:fragment];
	sendBufferSize += maxReadableLength;
	
	[self scheduleMaybeSendData];
	
	return maxReadableLength;
}

/**
 * Returns whether or not there is any data available to be read.
**/
- (BOOL)hasBytesAvailable
{
	return recvBufferSize > 0;
}

/**
 * Reads as much data as is available, up to the given maxLength.
 * The amount read may not be as much as maxLength, and one should check the length of the value returned.
 * If there is no data available, this method will immediately return 0.
**/
- (UInt32)read:(UInt8 *)buffer maxLength:(UInt32)maxLength
{
	// The recvBuffer is an array of PseudoTcpPacket's that we've received.
	// The packets are added to the array in their proper sequential order.
	
	if(recvBufferSize == 0) return 0;
	
	UInt32 amountRead = 0;
	
	while(([recvBuffer count] > 0) && (amountRead < maxLength))
	{
		PseudoTcpPacket *packet = [recvBuffer objectAtIndex:0];
		NSData *packetData = [packet data];
		
		UInt32 packetAvailableLength = [packetData length] - recvBufferOffset;
		UInt32 resultRemainingLength = maxLength - amountRead;
		
		if(packetAvailableLength <= resultRemainingLength)
		{
			// All available data from this packet can be added to the result
			void *subBuffer = buffer + amountRead;
			const void *subData = [packetData bytes] + recvBufferOffset;
			
			memcpy(subBuffer, subData, packetAvailableLength);
			
			// Update the amount of data read
			amountRead += packetAvailableLength;
			
			// Update the amount of data available in our recvBuffer
			recvBufferSize -= packetAvailableLength;
			
			// Update the recvSequence variable, which always refers to the first packet in the recvBuffer
			recvSequence += (UInt32)[packetData length];
			
			// We're finished with this packet, so we can remove it, and reset the offset
			[recvBuffer removeObjectAtIndex:0];
			recvBufferOffset = 0;
		}
		else
		{
			// Only a portion of data from this packet can be added to the result
			void *subBuffer = buffer + amountRead;
			const void *subData = [packetData bytes] + recvBufferOffset;
			
			memcpy(subBuffer, subData, resultRemainingLength);
			
			// Update the amount of data read
			amountRead += resultRemainingLength;
			
			// Update the amount of data available in our recvBuffer
			recvBufferSize -= resultRemainingLength;
			
			// We're not finished with this packet, but we do need to update the offset
			recvBufferOffset += resultRemainingLength;
		}
	}
	
	if(flags & kConnectionReset)
	{
		// The remote host has stopped sending and receiving data.
		// So no need to send any acks.
		
		if(recvBufferSize == 0)
		{
			// We've read to the end of the stream
			
			// Update state
			state = STATE_CLOSED;
			
			// Release TCP resources
			[self cleanup];
			
			// Notify delegate of closed socket
			if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
			{
				[delegate performSelector:@selector(onPseudoTcpDidClose:)
							   withObject:self
							   afterDelay:0.0
								  inModes:[udpSocket runLoopModes]];
			}
		}
	}
	else if(state == STATE_ESTABLISHED)
	{
		// Schedule window update to be sent
		[self scheduleDelayedAck];
	}
	
	return amountRead;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark State
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the current size of our receive window.
 * That is, how much data we have available in our recvBuffer.
**/
- (UInt32)recvWindow
{
	// Note: We don't bother implementing SWS avoidance here.
	// The reason being, if we implement Nagle's algorithm for sending from day one,
	// there's no need to worry about advertising a small window.
	
	return RECV_BUFFER_SIZE - recvBufferSize;
}

/**
 * Returns the sequence number we are expecting to receive next.
**/
- (UInt32)expectedSequence
{
	// Note: The recvSequence number refers to the sequence number of the first packet in the recvBuffer.
	// If the recvBuffer is empty, it refers to the sequence number we expect next.
	
	return recvSequence + recvBufferOffset + recvBufferSize;
}

/**
 * Returns the number of bytes available in the send buffer.
 * This method properly takes into account the size of the retransmissionQueue and the size of the sendBuffer.
**/
- (UInt32)spaceAvailableInSendBuffer
{
	// Remember: Although the retransmissionQueue and sendBuffer are separate,
	// they both combine to make up the conceptual send buffer.
	
	return SEND_BUFFER_SIZE - (retransmissionQueueSize + sendBufferSize);
}

/**
 * Returns the sequence number of the oldest byte sent and unacknowledged.
 * If there is no unacknowledged data, returns the sequence number of the next byte of data to send.
**/
- (UInt32)sendUnacknowledged
{
	if([retransmissionQueue count] > 0)
	{
		PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:0];
		return [packet sequence];
	}
	else
	{
		return sendSequence + sendBufferOffset;
	}
}

/**
 * Returns the sequence number of the next byte of data to be sent.
**/
- (UInt32)sendNext
{
	return sendSequence + sendBufferOffset;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark New Reno
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Updates the recover variable, and sets flags indicating that the recover variable is valid,
 * and that the next partial ack will be the first partial ack.
**/
- (void)setRecover
{
	if([retransmissionQueue count] > 0)
	{
		PseudoTcpPacket *firstPacket = [retransmissionQueue objectAtIndex:0];
		recover = [firstPacket sequence] + retransmissionQueueEffectiveSize;
		
		flags |= kRecover;
		flags |= kFirstPartial;
	}
}

/**
 * Marks the recover variable as invalid, and unsets new reno related flags.
**/
- (void)unsetRecover
{
	flags &= ~kRecover;
	flags &= ~kFirstPartial;
}

/**
 * Determines whether the given ack is a full or partial ack.
 * It is considered only a partial ack if recover is set, and the given ack is not greater than the highest
 * sequence number transmitted when recover was set.
**/
- (BOOL)isFullAck:(UInt32)ack
{
	if(!(flags & kRecover)) return YES;
	if([retransmissionQueue count] == 0) return YES;
	
	// The recover variable is within the retransmission window.
	// 
	// We also know the ack is within the retransmission window, because the processDataAck
	// method calls isAckWithinRetransmissionQueue before doing any processing.
	
	PseudoTcpPacket *startPacket = [retransmissionQueue objectAtIndex:0];
	
	UInt32 startSequence = [startPacket sequence];
	UInt32 endSequence = startSequence + retransmissionQueueSize;
	
	// Always be weary of wrapping sequence numbers...
	
	if(startSequence <= endSequence)
	{
		if(ack < recover)
			return NO;
		else
			return YES; 
	}
	else
	{
		// The window has wrapped
		
		if(ack >= startSequence)
		{
			if(recover >= startSequence)
			{
				// Neither ack or recover has wrapped
				if(ack < recover)
					return NO;
				else
					return YES;
			}
			else
			{
				// ack didn't wrap, but recover did.
				// ack < recover
				return NO;
			}
		}
		else
		{
			if(recover >= startSequence)
			{
				// ack wrapped, but recover didn't.
				// ack > recover
				return YES;
			}
			else
			{
				// Both ack and recover wrapped
				if(ack < recover)
					return NO;
				else
					return YES;
			}
		}
	}
}

/**
 * Returns whether or not this is the first partial ack received.
 * This determination is based on the kFirstPartial flag.
 * This flag is set in setRecover, and unset in unsetRecover.
 * If this method is called, and returns YES, further calls to it will return NO.
 * Only resetting the recover variable will allow it to return another YES.
**/
- (BOOL)isFirstPartialAck
{
	if(flags & kFirstPartial)
	{
		flags ^= kFirstPartial;
		return YES;
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Utility method to handle the repetitive task of sending a packet,
 * adding it to the retransmission queue, and starting a timer for it.
**/
- (void)sendPacket:(PseudoTcpPacket *)packet
{
	DDLogInfo(@"PseudoTcp: SEND: flg(%d%d%d%d) seq(%010u) ack(%010u) wnd(%05u) dat(%03u)",
			  [packet isRst]  ? 1 : 0, 
			  [packet isSack] ? 1 : 0,
			  [packet isAck]  ? 1 : 0,
			  [packet isSyn]  ? 1 : 0,
			  [packet sequence], [packet acknowledgement], [packet window], (unsigned)[[packet data] length]);
	
	// Send packet
	[udpSocket sendData:[packet packetData] withTimeout:NO_TIMEOUT tag:0];
	
	// With the exception of acks not carrying any data, we'll expect an ack for this packet
	if([packet isSyn] || [packet data])
	{
		// Add packet to retransmission queue
		[retransmissionQueue addObject:packet];
		retransmissionQueueSize += (UInt32)[[packet data] length];
		retransmissionQueueEffectiveSize += (UInt32)[[packet data] length];
		
		// Mark packet as counting towards the effective rxQ size
		[packet setIsRxQ:YES];
		
		// Store time we sent this packet
		[packet setFirstSent:[NSDate date]];
		
		// Start the retransmissionTimer, if it's not already started
		if(retransmissionTimer == nil)
		{
			retransmissionTimer = [[NSTimer timerWithTimeInterval:rto
														   target:self
														 selector:@selector(doTimeout:)
														 userInfo:nil
														  repeats:NO] retain];
			[self runLoopAddTimer:retransmissionTimer];
		}
	}
}

/**
 * Utility method to handle resending a packet from the retransmission queue.
**/
- (void)resendPacket:(PseudoTcpPacket *)packet
{
	if(![packet isSyn])
	{
		// Strip any old ack data from the packet
		[packet setIsAck:NO];
		[packet setIsSack:NO];
		[packet setAcknowledgement:0];
		
		// Maybe add ack data
		[self maybeAddAck:packet];
	}
	
	DDLogInfo(@"PseudoTcp: RSND: flg(%d%d%d%d) seq(%010u) ack(%010u) wnd(%05u) dat(%03u)",
			  [packet isRst]  ? 1 : 0,
			  [packet isSack] ? 1 : 0,
			  [packet isAck]  ? 1 : 0,
			  [packet isSyn]  ? 1 : 0,
			  [packet sequence], [packet acknowledgement], [packet window], (unsigned)[[packet data] length]);
	
	// Mark packet as being retransmitted
	[packet setWasRetransmitted:YES];
	
	// If packet wasn't part of effective rxQ size, it is now
	if(![packet isRxQ])
	{
		[packet setIsRxQ:YES];
		retransmissionQueueEffectiveSize += (UInt32)[[packet data] length];
	}
	
	// Send packet
	[udpSocket sendData:[packet packetData] withTimeout:NO_TIMEOUT tag:0];
	
	// This method is not used to send plain acks, because they are never stored in the retransmission queue.
	// 
	// There's no need to add this packet to the retransmission queue, because it's already in the queue.
	
	// Start the retransmissionTimer, if it's not already started
	if(retransmissionTimer == nil)
	{
		retransmissionTimer = [[NSTimer timerWithTimeInterval:rto
													   target:self
													 selector:@selector(doTimeout:)
													 userInfo:nil
													  repeats:NO] retain];
		[self runLoopAddTimer:retransmissionTimer];
	}
}

- (void)cleanup
{
	NSAssert(state == STATE_CLOSED, @"Cleanup called in improper state");
	
	// Remove all objects from the receive buffer
	[recvBuffer removeAllObjects];
	recvBufferOffset = 0;
	recvBufferSize = 0;
	
	// Clear the ack timer to prevent any pending acks from being sent
	[ackTimer invalidate];
	[ackTimer release];
	ackTimer = nil;
	
	// Remove all objects from the send buffer
	[sendBuffer removeAllObjects];
	sendBufferOffset = 0;
	sendBufferSize = 0;
	
	// Remove all objects from the retransmissionQueue
	[retransmissionQueue removeAllObjects];
	retransmissionQueueSize = 0;
	retransmissionQueueEffectiveSize = 0;
	
	// Clear the retransmission timer
	[retransmissionTimer invalidate];
	[retransmissionTimer release];
	retransmissionTimer = nil;
	
	// Clear the persist timer
	[persistTimer invalidate];
	[persistTimer release];
	persistTimer = nil;
	
	// Clear the keep alive timer
	[keepAliveTimer invalidate];
	[keepAliveTimer release];
	keepAliveTimer = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Handshake
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Processes an opening syn packet.
 * We're either in STATE_LISTEN or STATE_SYN_RECEIVED.
 * The latter may occur if our syn-ack gets lost, and they have to retransmit their opening syn.
**/
- (void)processOpeningSyn:(PseudoTcpPacket *)synPacket
{
	DDLogVerbose(@"PseudoTcp: processOpeningSyn: seq(%010u) ack(%010u) wnd(%05u)",
				 [synPacket sequence], [synPacket acknowledgement], [synPacket window]);
	
	recvSequence = [synPacket sequence] + 1;
	sendWindow   = [synPacket window];
	
	// Check for SACK support
	receiverSupportsSack = [synPacket isSack];
	DDLogVerbose(@"PseudoTcp: receiverSupportsSack: %d", receiverSupportsSack);
	
	// Create and send our opening SYN-ACK packet
	PseudoTcpPacket *synAckPacket = [[[PseudoTcpPacket alloc] init] autorelease];
	[synAckPacket setSequence:(sendSequence - 1)];
	[synAckPacket setAcknowledgement:recvSequence];
	[synAckPacket setWindow:[self recvWindow]];
	[synAckPacket setIsSyn:YES];
	[synAckPacket setIsAck:YES];
	[synAckPacket setIsSack:YES];
	
	[self sendPacket:synAckPacket];
	
	// Update state
	state = STATE_SYN_RECEIVED;
}

/**
 * Process an opening syn-ack packet.
 * We're either in the STATE_SYN_SENT or STATE_ESTABLISHED.
 * The latter may occur if our final ack gets lost, and they have to retransmit their opening syn-ack.
**/
- (void)processOpeningSynAck:(PseudoTcpPacket *)synAckPacket
{
	DDLogVerbose(@"PseudoTcp: processOpeningSynAck: seq(%010u) ack(%010u) wnd(%05u)",
				 [synAckPacket sequence], [synAckPacket acknowledgement], [synAckPacket window]);
	
	// If this is the first time we've received the syn-ack, we can remove the syn from the retransmission queue.
	// Since the syn-ack may be sent several times (if our ack response is lost), we should double-check everything.
	if([retransmissionQueue count] > 0)
	{
		PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:0];
		if([packet isSyn])
		{
			// The ack is for our opening syn, which we can now remove from the retransmission queue
			[retransmissionQueue removeObjectAtIndex:0];
			
			// And don't forget to invalidate the timer we setup for the syn packet
			[retransmissionTimer invalidate];
			[retransmissionTimer release];
			retransmissionTimer = nil;
		}
	}
	
	// Extract syn data from the packet
	recvSequence = [synAckPacket sequence] + 1;
	sendWindow   = [synAckPacket window];
	
	// Check for SACK support
	receiverSupportsSack = [synAckPacket isSack];
	DDLogVerbose(@"PseudoTcp: receiverSupportsSack: %d", receiverSupportsSack);
	
	// Create and send our opening ack packet
	PseudoTcpPacket *ackPacket = [[[PseudoTcpPacket alloc] init] autorelease];
	[ackPacket setAcknowledgement:recvSequence];
	[ackPacket setWindow:[self recvWindow]];
	[ackPacket setIsAck:YES];
	
	[self sendPacket:ackPacket];
	
	if(state != STATE_ESTABLISHED)
	{
		// Update state
		state = STATE_ESTABLISHED;
		
		// Inform delegate that the connection is open
		if([delegate respondsToSelector:@selector(onPseudoTcpDidOpen:)])
		{
			[delegate onPseudoTcpDidOpen:self];
		}
		
		// If the delegate hasn't already filled the majority of the send buffer in the onPseudoTcpDidOpen method
		if([self spaceAvailableInSendBuffer] > (SEND_BUFFER_SIZE / 4))
		{
			// Inform delegate that we can accept data to be sent
			if([delegate respondsToSelector:@selector(onPseudoTcpCanAcceptBytes:)])
			{
				[delegate onPseudoTcpCanAcceptBytes:self];
			}
		}
	}
}

/**
 * Process an opening ack packet.
 * We should be in STATE_SYN_RECEIVED.
**/
- (void)processOpeningAck:(PseudoTcpPacket *)ackPacket
{
	DDLogVerbose(@"PseudoTcp: processOpeningAck: seq(%010u) ack(%010u) wnd(%05u)",
				 [ackPacket sequence], [ackPacket acknowledgement], [ackPacket window]);
	
	// Note: This method is ONLY called once.
	
	// The ack is for our opening syn-ack, which we can now remove from the retransmission queue
	[retransmissionQueue removeObjectAtIndex:0];
	
	// And don't forget to invalidate the timer we setup for the syn-ack packet
	[retransmissionTimer invalidate];
	[retransmissionTimer release];
	retransmissionTimer = nil;
	
	// Update state
	state = STATE_ESTABLISHED;
	
	// Inform delegate that the connection is open
	if([delegate respondsToSelector:@selector(onPseudoTcpDidOpen:)])
	{
		[delegate onPseudoTcpDidOpen:self];
	}
	
	// If the delegate hasn't already filled the majority of the send buffer in the onPseudoTcpDidOpen method
	if([self spaceAvailableInSendBuffer] > (SEND_BUFFER_SIZE / 4))
	{
		// Inform delegate that we can accept data to be sent
		if([delegate respondsToSelector:@selector(onPseudoTcpCanAcceptBytes:)])
		{
			[delegate onPseudoTcpCanAcceptBytes:self];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ACK
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Process an ack packet for data we've sent.
 * We should be in STATE_ESTABLISHED.
 *
 * The paacket may or may not include data, but the data isn't processed by this method.
 * Only the ack part is processed in this method.
**/
- (void)processDataAck:(PseudoTcpPacket *)ackPacket
{
	if(![self isAckWithinRetransmissionQueue:[ackPacket acknowledgement]])
	{
		// The ack doesn't apply to any packets in our retransmissionQueue.
		// It must be an old ack.
		// We can ignore it, as it doesn't affect anything.
		return;
	}
	
	// Check to see if packet contains a selective ack.
	// If so, remove the indicated packet from the retransmission queue.
	
	BOOL isEffectiveSelectiveAck = NO;
	
	if([ackPacket isSack])
	{
		unsigned i;
		for(i = 0; i < [retransmissionQueue count]; i++)
		{
			PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:i];
			
			if([packet sequence] == [ackPacket sackSequence])
			{
				DDLogInfo(@"PseudoTcp: Received SACK %u", [ackPacket sackSequence]);
				
				if([packet isRxQ])
				{
					retransmissionQueueEffectiveSize -= (UInt32)[[packet data] length];
					isEffectiveSelectiveAck = YES;
				}
				
				retransmissionQueueSize -= (UInt32)[[packet data] length];
				[retransmissionQueue removeObjectAtIndex:i];
				
				break;
			}
		}
	}
	
	// Check to see if this is a duplicate ack.
	// In the event of duplicate acks we may need to perform fast retransmit or fast recovery.
	// 
	// A duplicate ACK is a packet with the ACK bit set which acknowledges a previously acknowledged packet, AND
	// and is not simply a window update (changes the receiver's advertised window).
	// This method would not have been called if the ACK bit was not set.
	
	BOOL windowUpdateOnly = NO;
	BOOL isPartialAck = NO;
	
	if([ackPacket acknowledgement] == lastAck)
	{
		// This may not actually be a duplicate ack - it may simply be a window size update.
		// It may also be a response to an empty window probe.
		
		if(([ackPacket window] > 0) && ([ackPacket window] == sendWindow))
		{
			lastAckCount++;
			
			DDLogInfo(@"PseudoTcp: Duplicate Ack count: %u", (unsigned)lastAckCount);
			
			if(lastAckCount < 3)
			{
				// Todo: RFC 3042
				
				if(isEffectiveSelectiveAck)
				{
					// The ACK stayed the same, but SACK removed some data from the retransmissionQueue
					[self maybeSendData];
				}
			}
			else if(lastAckCount == 3)
			{
				DDLogInfo(@"PseudoTcp: Fast Retransmit");
				
				// When the third duplicate ACK in a row is received, decrease ssthresh according to RFC 2581.
				// Retransmit the missing segment.
				// Set cwnd to ssthresh plus 3 times the segment size. This inflates the congestion window
				// by the number of segments that have left the network and which the other end has cached.
				
				ssthresh = MAX((retransmissionQueueEffectiveSize / 2), (2 * DEFAULT_MTU));
				
				[self resendPacketWithSequence:lastAck];
				
				cwnd = ssthresh + (3 * DEFAULT_MTU);
				
				// New Reno (RFC 3782):
				// In addition, record the highest sequence number transmitted in the recover variable.
				[self setRecover];
				
				if(isEffectiveSelectiveAck)
				{
					// The ACK stayed the same, but SACK removed some data from the retransmissionQueue
					[self maybeSendData];
				}
			}
			else if(lastAckCount > 3)
			{
				DDLogInfo(@"PseudoTcp: Fast Recovery");
				
				// Each time another duplicate ACK arrives, increment cwnd by the segment size.
				// This inflates the congestion window for the additional segment that has left the network.
				// Transmit a packet, if allowed by the new value of cwnd.
				
				cwnd += DEFAULT_MTU;
				
				[self maybeSendData];
			}
			
			// We've already processed this ack once, no need to do it again
			return;
		}
		else
		{
			windowUpdateOnly = YES;
		}
	}
	else
	{
		if(lastAckCount >= 3)
		{
			// As per new reno, check for full or partial acknowledegment
			
			if([self isFullAck:[ackPacket acknowledgement]])
			{
				DDLogInfo(@"PseudoTcp: Full ACK - Exiting Fast Recovery");
				
				// The ACK acknowledges all the intermediate segments sent between the original transmission
				// of the lost segment and the receipt of the ghird duplicate ACK.
				// Set cwnd to ssthresh (the value set in step 1).
				// This is termed "deflating" the window.
				
				cwnd = ssthresh;
				
				// Exit fast recovery
				[self unsetRecover];
				lastAck = [ackPacket acknowledgement];
				lastAckCount = 0;
			}
			else
			{
				DDLogInfo(@"PseudoTcp: Partial ACK");
				
				// Retranmit the first unacknowledged segment.
				// Deflate the congestion window by the amount of new data ackowledged by the ACK.
				// Do not exit fast recovery.
				// If any duplicate ACKs subsequently arrive, continue fast recovery procedure.
				
				lastAck = [ackPacket acknowledgement];
				[self resendPacketWithSequence:lastAck];
				
				// Notice that we do not reset lastAckCount.
				// This means that further duplicate ACKs will follow fast recovery above.
				
				// We'll do the deflation stuff below after we've determined how much data was acked.
				isPartialAck = YES;
			}
		}
		else
		{
			lastAck = [ackPacket acknowledgement];
			lastAckCount = 0;
		}
	}
	
	if(windowUpdateOnly)
	{
		// If the window update was a response to an empty window probe,
		// and the window size is still zero, then update the packet to prevent a timeout.
		
		if([ackPacket window] == 0)
		{
			PseudoTcpPacket *packet = [retransmissionQueue count] > 0 ? [retransmissionQueue objectAtIndex:0] : nil;
			
			if([packet isEmptyWindowProbe])
			{
				DDLogVerbose(@"PseudoTcp: Receiving empty window probe ack - window is still empty");
				[packet setFirstSent:[NSDate date]];
			}
		}
	}
	else
	{
		// Remove all packets from the retransmission queue which are acknowledged by this packet.
		// 
		// Also, we need to make a note if any of the acknowledged packets were retransmitted,
		// because ack's for retransmitted packets are not to be used in updating the RTO.
		// 
		// And we also need to know the sent time of the oldest packet being acknowledged.
		// Since packets are stored in the retransmission queue accorinding to sequence number,
		// this will be the sent time of the first ack'd packet.
		
		uint numAckedPackets = 0;
		uint numAckedData = 0;
		BOOL wasRetransmitted = NO;
		NSDate *sentTime = nil;
		
		while([retransmissionQueue count] > 0)
		{
			PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:0];
			
			if([self doesAck:[ackPacket acknowledgement] absolvePacket:packet])
			{
				numAckedPackets++;
				numAckedData += [[packet data] length];
				wasRetransmitted = wasRetransmitted || [packet wasRetransmitted];
				
				if(sentTime == nil)
				{
					// We need to retain the sentTime or else it will get released when we release the packet
					sentTime = [[[packet firstSent] retain] autorelease];
				}
				
				if([packet isRxQ])
				{
					retransmissionQueueEffectiveSize -= (UInt32)[[packet data] length];
				}
				
				retransmissionQueueSize -= (UInt32)[[packet data] length];
				[retransmissionQueue removeObjectAtIndex:0];
			}
			else
			{
				break;
			}
		}
		
		DDLogVerbose(@"PseudoTcp: processDataAck: numAckedPackets: %u", numAckedPackets);
		
		if(numAckedPackets == 0)
		{
			// Not sure how this could be possible given the initial check we did when starting this method
			DDLogWarn(@"PseudoTcp: processDataAck: numAckedPackets is zero!");
			return;
		}
		
		// Update RTO and related variables
		
		if(wasRetransmitted)
		{
			// A TCP implementation may clear SRTT and RTTVAR after backing off the timer multiple times as
			// it is unlikely that the current SRTT and RTTVAR are bogus in this situation.
			srtt = 0.0;
			rttvar = 0.0;
		}
		else
		{
			NSTimeInterval rtt = [sentTime timeIntervalSinceNow] * -1.0;
			
			// Check for a valid rtt time
			if((rtt > 0.0) && (rtt <= 60.0))
			{
				// Update RTT related variables according to RFC 2988
				
				if(srtt == 0.0)
				{
					// This is the first RTT measurement that has been made,
					// or the first that has been made since a retransmission reset the values of srtt and rttvar.
					srtt = rtt;
					rttvar = srtt / 2.0;
				}
				else
				{
					// These are the suggested values of alpha and beta, as per RFC 2988
					double alpha = 1.0 / 8.0;
					double beta  = 1.0 / 4.0;
					
					rttvar = (1.0 - beta) * rttvar + beta * fabs(srtt - rtt);
					srtt = (1.0 - alpha) * srtt + alpha * rtt;
				}
				
				// G = clock granularity -> how precise our timer is.
				// According to the NSTimer documentation: the effective resolution of
				// the time interval for an NSTimer is limited to on the order of 50-100 milliseconds.
				// In practice, I would say it's actually more like 1-8 milliseconds.
				double G = 0.05;
				
				// I don't know WTF K is supposed to be, but I'm told its value is simply 4
				double K = 4.0;
				
				rto = srtt + MAX(G, K*rttvar);
				
				// From RFC 2988:
				// Whenever RTO is computed, if it is less than 1 second then the RTO SHOULD be rounded up to 1 second
				if(rto < 1.0 )
				{
					rto = 1.0;
				}
				
				DDLogVerbose(@"rtt(%1.3f) srtt(%1.3f) rttvar(%1.3f) rto(%1.3f)", rtt, srtt, rttvar, rto);
			}
			else
			{
				// The RTT doesn't appear to be valid...
				// Maybe the user changed the clock, changed time zones, or daylight savings time kicked in.
				// Whatever the case, we obviously can't use this tainted RTT to update the RTO.
				
				// How did we come up with the 60 seconds limit?
				// We use a maximum RTO of 60 seconds, so anything over 60 seconds would have been retransmitted.
				// But we've already checked to make sure none of the ack'd packets were retransmitted.
			}
		}
		
		// Stop or restart the retransmission timer.
		// Note: This must happen AFTER we've updated the RTO value.
		
		if(isPartialAck)
		{
			// For the FIRST partial ack that arrives during fast recovery, reset the retransmission timer.
			// Subsequent partial acks do not affect the retransmission timer.
			
			if([self isFirstPartialAck])
			{
				[retransmissionTimer invalidate];
				[retransmissionTimer release];
				
				retransmissionTimer = [[NSTimer timerWithTimeInterval:rto
															   target:self
															 selector:@selector(doTimeout:)
															 userInfo:nil
															  repeats:NO] retain];
				[self runLoopAddTimer:retransmissionTimer];
			}
		}
		else
		{
			if(retransmissionQueueSize > 0)
			{
				// When an ACK is received that acknowledges new data, restart the retransmission timer.
				[retransmissionTimer invalidate];
				[retransmissionTimer release];
				
				retransmissionTimer = [[NSTimer timerWithTimeInterval:rto
															   target:self
															 selector:@selector(doTimeout:)
															 userInfo:nil
															  repeats:NO] retain];
				[self runLoopAddTimer:retransmissionTimer];
			}
			else
			{
				// When all outstanding data has been acknowledged, turn off the retransmission timer.
				[retransmissionTimer invalidate];
				[retransmissionTimer release];
				retransmissionTimer = nil;
			}
		}
		
		// Update congestion window
		
		if(isPartialAck)
		{
			// From RFC 3782:
			// Deflate the congestion window by the amount of new data acknowledged.
			// If the partial ack acknowledges at least one SMSS of new data, then add back SMSS bytes to cwnd.
			
			// Note: cwnd should theoretically always be greater than numAckedData
			
			if(cwnd > numAckedData)
			{
				cwnd -= numAckedData;
			}
			if(numAckedData >= DEFAULT_MTU)
			{
				cwnd += DEFAULT_MTU;
			}
		}
		else
		{
			// From RFC 2581:
			// The slow start algorithm is used when cwnd < ssthresh, while
			// the congestion avoidance algorithm is used when cwnd > ssthresh.
			// When cwnd and ssthresh are equal the sender may use either slow start or congestion avoidance.
			
			if(cwnd <= ssthresh)
			{
				// We're in slow start
				
				if(cwnd < UINT32_MAX - DEFAULT_MTU)
				{
					cwnd += DEFAULT_MTU;
				}
				
				DDLogVerbose(@"slow start: cwnd(%05u)", cwnd);
			}
			else
			{
				// We're in congestion avoidance
				// 
				// Note: Since integer arithmetic is used, the congestion avoidance formula for incrementing cwnd can
				// fail when the congestion window is very large (larger than SMSS * SMSS). If the formula yields an
				// increase of 0, the result SHOULD be rounded up to an increase of 1 byte.
				
				if(cwnd < UINT32_MAX - 1)
				{
					cwnd += MAX(1, DEFAULT_MTU * DEFAULT_MTU / cwnd);
				}
				
				DDLogVerbose(@"congestion avoidance: cwnd(%05u)", cwnd);
			}
		}
	}
	
	// Update sliding window variables
	sendWindow = [ackPacket window];
	
	if((persistTimer != nil) && (sendWindow > 0))
	{
		// We're done sending empty window probes
		[persistTimer invalidate];
		[persistTimer release];
		persistTimer = nil;
	}
	
	if(flags & kForbidWrites)
	{
		// Maybe send more data if we have it, and if the various sliding window mechanisms allow it
		[self maybeSendData];
		
		// Maybe send the RST if all queued data has been sent and acked
		[self maybeSendRst];
	}
	else
	{
		// We may want to inform the delegate that we can accept more data to be sent.
		// However, we don't want to inform them after every ack, so we wait until we can accept larger data chunks.
		if([self spaceAvailableInSendBuffer] > (SEND_BUFFER_SIZE / 4))
		{
			if([delegate respondsToSelector:@selector(onPseudoTcpCanAcceptBytes:)])
			{
				[delegate onPseudoTcpCanAcceptBytes:self];
			}
		}
		
		// Maybe send more data if we have it, and if the various sliding window mechanisms allow it.
		// Do this after we've queried the delegate for more data to prevent sending small fragments.
		[self maybeSendData];
	}
}

/**
 * Checks to see if the given ack fits within our retransmission queue.
 * That is, that the ack is between sendUnacknowledged and sendNext.
**/
- (BOOL)isAckWithinRetransmissionQueue:(UInt32)ack
{
	UInt32 sendUnacknowledged = [self sendUnacknowledged];
	UInt32 sendNext = [self sendNext];
	
	// Always be weary of wrapping sequence numbers...
	
	if(sendUnacknowledged <= sendNext)
	{
		return ((ack >= sendUnacknowledged) && (ack <= sendNext));
	}
	else
	{
		return ((ack >= sendUnacknowledged) || (ack <= sendNext));
	}
}

/**
 * Utility method to compare acks and sequence numbers.
 * Use this method instead of a simple integer comparison because this method properly handles wrapping.
 * 
 * This method is not designed to work with syn packets.
**/
- (BOOL)doesAck:(UInt32)ack absolvePacket:(PseudoTcpPacket *)packet
{
	UInt32 sendUnacknowledged = [self sendUnacknowledged];
	UInt32 sendNext = [self sendNext];
	
	UInt32 endSeq = [packet sequence] + (UInt32)[[packet data] length];
	
	// Note: sendUnacknowledged points to the sequence number of the oldest byte sent but yet un-ack'd.
	// Note: sendNext points to the sequence number of the next byte of data to send.
	
	// Always be weary of wrapping sequence numbers...
	
	if(sendUnacknowledged <= sendNext)
	{
		if((ack >= sendUnacknowledged) && (ack <= sendNext))
		{
			// The send window hasn't wrapped, so the packet is absolved only if it also hasn't wrapped
			// and is still less than or equal to the ack.
			
			if(endSeq >= sendUnacknowledged)
				return endSeq <= ack;
			
			return NO;
		}
		else
		{
			// This is a delayed ack that doesn't apply to any unacknowledged data
			return NO;
		}
	}
	else
	{
		// The send window has wrapped, so we'll need to take this into consideration
		
		if(ack >= sendUnacknowledged)
		{
			// The ack itself hasn't wrapped, so the packet is absolved only if it also hasn't wrapped
			// and is still less than or equal to the ack.
			
			if(endSeq >= sendUnacknowledged)
				return endSeq <= ack;
			
			return NO;
		}
		else if(ack <= sendNext)
		{
			// The ack has wrapped, so the packet is absolved only if it hasn't wrapped,
			// or if it has wrapped and is still less than or equal to the ack.
			
			if(endSeq >= sendUnacknowledged)
				return YES;
			else
				return endSeq <= ack;
		}
		else
		{
			// This is a delayed ack that doesn't apply to any unacknowledged data
			return NO;
		}
	}
}

/**
 * Schedules an ack to be sent, after a short time period.
 * If an ack is already scheduled to be sent, this method does nothing.
**/
- (void)scheduleDelayedAck
{
	if(ackTimer == nil)
	{
		ackTimer = [[NSTimer timerWithTimeInterval:ACK_TIMEOUT
											target:self
										  selector:@selector(doAckTimeout:)
										  userInfo:nil
										   repeats:NO] retain];
		[self runLoopAddTimer:ackTimer];
	}
}

/**
 * Immediately sends an ack.
**/
- (void)sendAckNow
{
	// Remove any scheduled ack
	[ackTimer invalidate];
	[ackTimer release];
	ackTimer = nil;
	
	// Clear the tally of un-acked packets
	unackedPackets = 0;
	
	// Send the ack
	PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] init] autorelease];
	[packet setAcknowledgement:[self expectedSequence]];
	[packet setWindow:[self recvWindow]];
	[packet setIsAck:YES];
	
	[self sendPacket:packet];
}

/**
 * Immediately sends an ack, with the given sack as well.
**/
- (void)sendSackNow:(UInt32)sackSequence
{
	// Remove any scheduled ack
	[ackTimer invalidate];
	[ackTimer release];
	ackTimer = nil;
	
	// Clear the tally of un-acked packets
	unackedPackets = 0;
	
	// Send the ack
	PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] init] autorelease];
	[packet setAcknowledgement:[self expectedSequence]];
	[packet setWindow:[self recvWindow]];
	[packet setIsAck:YES];
	
	if(receiverSupportsSack)
	{
		[packet setIsSack:YES];
		[packet setSackSequence:sackSequence];
	}
	
	[self sendPacket:packet];
}

/**
 * If there is a delayed ack waiting to be sent, this method tacks the ack onto the given data packet,
 * thus combining the two, and decreasing network traffic while increasing efficiency.
**/
- (void)maybeAddAck:(PseudoTcpPacket *)dataPacket
{
	if(ackTimer && ![dataPacket isAck])
	{
		// Remove scheduled ack
		[ackTimer invalidate];
		[ackTimer release];
		ackTimer = nil;
		
		// Clear the tally of un-acked packets
		unackedPackets = 0;
		
		// Add ack info to existing data packet
		[dataPacket setAcknowledgement:[self expectedSequence]];
		[dataPacket setWindow:[self recvWindow]];
		[dataPacket setIsAck:YES];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Data
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Compares two numbers within the context of the receive window.
 * Both numbers are expected to be within the current receive window.
 * Use this method instead of a simple integer comparison because this method properly handles wrapping.
 * 
 * NSOrderedAscending  -> numA < numB
 * NSOrderedDescending -> numA > numB
 * NSOrderedSame       -> numA = numB
**/
- (NSComparisonResult)compareWithinRecvWindow:(UInt32)numA to:(UInt32)numB
{
	UInt32 startSequence = recvSequence + recvBufferOffset + recvBufferSize;
	UInt32 endSequence = recvSequence + recvBufferOffset + RECV_BUFFER_SIZE;
	
	// Always be weary of wrapping sequence numbers...
	
	if(startSequence <= endSequence)
	{
		if(numA < numB)
			return NSOrderedAscending;
		if(numA > numB)
			return NSOrderedDescending;
		else
			return NSOrderedSame; 
	}
	else
	{
		// The window has wrapped
		
		if(numA >= startSequence)
		{
			if(numB >= startSequence)
			{
				// Neither numA or numB has wrapped
				if(numA < numB)
					return NSOrderedAscending;
				if(numA > numB)
					return NSOrderedDescending;
				else
					return NSOrderedSame; 
			}
			else
			{
				// numA didn't wrap, but numB did.
				// numA < numB
				return NSOrderedAscending;
			}
		}
		else
		{
			if(numB >= startSequence)
			{
				// numA wrapped, but numB didn't.
				// numA > numB
				return NSOrderedDescending;
			}
			else
			{
				// Both numA and numB wrapped
				if(numA < numB)
					return NSOrderedAscending;
				if(numA > numB)
					return NSOrderedDescending;
				else
					return NSOrderedSame; 
			}
		}
	}
}

/**
 * Processes the data from the given packet.
**/
- (void)processData:(PseudoTcpPacket *)dataPacket
{
	// Check to make sure there's room in the recvBuffer for this packet
	if([self doesPacketFitInRecvWindow:dataPacket])
	{
		// Check to see if this is the sequence number we're expecting next
		if([dataPacket sequence] == [self expectedSequence])
		{
			// Append the packet to our recvBuffer
			[recvBuffer addObject:dataPacket];
			recvBufferSize += [[dataPacket data] length];
			unackedPackets++;
			
			// Add any out-of-order data that can be added.
			// Remember: the recvOutOfOrderBuffer is kept sorted also.
			
			while([recvOutOfOrderBuffer count] > 0)
			{
				PseudoTcpPacket *packet = [recvOutOfOrderBuffer objectAtIndex:0];
				
				// We knew, at the point when we added the packet to the out-of-order buffer, that
				// the packet was within the receive window at that time.
				// However, if the remote host screwed up and sent data fragments that overlapped,
				// then the packet may no longer be within the receive window.
				
				if([self doesPacketFitInRecvWindow:packet])
				{
					if([packet sequence] == [self expectedSequence])
					{
						// Append the packet to the recvBuffer
						[recvBuffer addObject:packet];
						recvBufferSize += [[packet data] length];
						unackedPackets++;
						
						// Remove the packet from the recvOutOfOrderBuffer
						[recvOutOfOrderBuffer removeObjectAtIndex:0];
					}
					else
					{
						// The packet is still out-of-order.
						// Since we know the out-of-order buffer is sorted, this means
						// we don't have any more data we can append to the receive buffer.
						break;
					}
				}
				else
				{
					// Found a packet that overlapped existing data within receive buffer.
					// Remove it from the out-of-order buffer, and continue looking.
					[recvOutOfOrderBuffer removeObjectAtIndex:0];
				}
			}
			
			if(unackedPackets >= 2)
			{
				// According to the TCP guidelines:
				// In a stream of full-sized segments there SHOULD be an ack for at least every second segment.
				// 
				// Furthermore, according to RFC 2581, section 4.2:
				// It is desireable [to immediately acknowledge] at least every second segment, regardless of size.
				[self sendAckNow];
				
				// We'll inform the delegate after the ack has been sent (in onUdpSocket:didSendDataWithTag:)
				flags |= kNewDataAvailable;
			}
			else
			{
				// We've only received a small amount of data, so we'll delay our ack.
				// In the event that we receive more data prior to the ack timer expiring, the ack will
				// immediately be sent, and the ack timer will get reset.
				[self scheduleDelayedAck];
				
				// Inform the delegate of the new data
				if([delegate respondsToSelector:@selector(onPseudoTcpHasBytesAvailable:)])
				{
					[delegate onPseudoTcpHasBytesAvailable:self];
				}
			}
		}
		else
		{
			// We received an out-of-order packet.
			// Add the packet to the out-of-order buffer.
			// 
			// Remember to keep the out-of-order buffer sorted by sequence number,
			// and not to add the same packet twice.
			
			BOOL isDuplicatePacket = NO;
			NSUInteger index = 0;
			
			while(index < [recvOutOfOrderBuffer count])
			{
				PseudoTcpPacket *packet = [recvOutOfOrderBuffer objectAtIndex:index];
				
				// Always be weary of wrapping sequence numbers...
				NSComparisonResult cmp = [self compareWithinRecvWindow:[dataPacket sequence] to:[packet sequence]];
				
				if(cmp == NSOrderedAscending)
				{
					// [dataPacket sequence] < [packet sequence]
					// 
					// We found the spot in which to insert the packet
					break;
				}
				else if(cmp == NSOrderedDescending)
				{
					// [dataPacket sequence > [packet sequence]
					// 
					// We still haven't found the spot in which to insert the newly received data packet
					index++;
				}
				else
				{
					// [dataPacket sequence] == [packet sequence]
					// 
					// We've already received this data packet, and it already exists in the out-of-order buffer.
					// There's no need to add it again.
					isDuplicatePacket = YES;
					break;
				}
			}
			
			if(!isDuplicatePacket)
			{
				[recvOutOfOrderBuffer insertObject:dataPacket atIndex:index];
				
				// In order to facilitate fast-retrasmit, we must send an ack immediately
				// We also selectively ack the packet we've received and added to our outOfOrder buffer
				[self sendSackNow:[dataPacket sequence]];
			}
			else
			{
				// In order to facilitate fast-retrasmit, we must send an ack immediately
				[self sendAckNow];
			}
		}
	}
	else
	{
		// We either received a packet that we already have (within recvBuffer),
		// or the remote host sent a packet that simply didn't fit in our existing receive window.
		// In either case, we'll send a regular ack to inform the remote host of our current situation.
		
		[self sendAckNow];
	}
}

/**
 * Checks to see if the given packet fits within our receive window somewhere.
 * That is, that the packet hasn't already been received, and that it doesn't overflow our receive buffer.
 * The packet may or may not be the next exepected sequence number.
**/
- (BOOL)doesPacketFitInRecvWindow:(PseudoTcpPacket *)packet
{
	UInt32 startSequence = recvSequence + recvBufferOffset + recvBufferSize;
	UInt32 endSequence = recvSequence + recvBufferOffset + RECV_BUFFER_SIZE;
	
	UInt32 packetStartSequence = [packet sequence];
	UInt32 packetEndSequence = packetStartSequence + (UInt32)[[packet data] length];
	
	// Always be weary of wrapping sequence numbers...
	
	if(startSequence <= endSequence)
	{
		if(packetStartSequence <= packetEndSequence)
		{
			// Normal situation
			return ((packetStartSequence >= startSequence) && (packetEndSequence <= endSequence));
		}
		else
		{
			// Window sequence numbers didn't wrap, but packet sequence numbers did.
			// The packetEndSequence must be past the endSequence.
			return NO;
		}
	}
	else
	{
		if(packetStartSequence <= packetEndSequence)
		{
			// The window sequence numbers wrapped, but the packet sequence numbers didn't.
			// The endSequence must be past the packetEndSequence, so we need only check the start sequence numbers.
			return packetStartSequence >= startSequence;
		}
		else
		{
			// Both the window sequence numbers and the packet sequence numbers wrapped.
			// Mathematically, we can treat this the same as the normal situation.
			return ((packetStartSequence >= startSequence) && (packetEndSequence <= endSequence));
		}
	}
}

/**
 * Puts a maybeSendData on the run loop.
**/
- (void)scheduleMaybeSendData
{
	[self performSelector:@selector(maybeSendData) withObject:nil afterDelay:0.0 inModes:[udpSocket runLoopModes]];
}

/**
 * Sends data if data can and should be sent.
**/
- (void)maybeSendData
{
	DDLogVerbose(@"PseudoTcp: maybeSendData: sendWindow(%u) cwnd(%u) rxEffectiveSize(%u) rxSize(%u)",
				 sendWindow, cwnd, retransmissionQueueEffectiveSize, retransmissionQueueSize);
	
	// Determine how much data we have available in our effective send window.
	// The effective send window is the minimum of:
	// - the send window advertised by the remote host
	// - our congestion window
	
	UInt32 effectiveWindow = MIN(sendWindow, cwnd);
	
	if(effectiveWindow <= retransmissionQueueEffectiveSize)
	{
		// We've reached our limit on how much we can send
		
		// Check to see if this is due to an empty send window
		if(sendWindow == 0)
		{
			[self maybeScheduleEmptyWindowProbe];
		}
		
		return;
	}
	
	UInt32 availableWindowSize = effectiveWindow - retransmissionQueueEffectiveSize;
	
	// Determine how much data we can send
	UInt32 availableSendSize = sendBufferSize + (retransmissionQueueSize - retransmissionQueueEffectiveSize);
	UInt32 maxSendSize = MIN(availableSendSize, availableWindowSize);
	
	// Loop sending data until we run out of data to send, or until we've filled our effective send window
	while(maxSendSize > 0)
	{
		UInt32 maxPacketDataLength = MIN(maxSendSize, DEFAULT_MTU);
		
		// Nagle's algorithm
		if(maxPacketDataLength < DEFAULT_MTU)
		{
			if(retransmissionQueueEffectiveSize > 0)
			{
				// Don't send a tiny little fragment now.
				// Wait until we have a full fragment, or until there is no more unacknowledged data.
				return;
			}
		}
		
		PseudoTcpPacket *packet = nil;
		
		if(retransmissionQueueSize > retransmissionQueueEffectiveSize)
		{
			// Resend OLD data
			
			// The effective size is smaller than the actual size because a retransmission timer expired.
			// Thus, we have to resend parts of the retransmission queue.
			
			UInt32 totalSize = 0;
			
			unsigned i;
			for(i = 0; i < [retransmissionQueue count] && packet == nil; i++)
			{
				if(totalSize == retransmissionQueueEffectiveSize)
				{
					packet = [retransmissionQueue objectAtIndex:i];
				}
				else
				{
					totalSize += (UInt32)[[[retransmissionQueue objectAtIndex:i] data] length];
				}
			}
			
			if(packet == nil)
			{
				DDLogError(@"PseudoTcp: maybeSendData: invalid rxQSize or rxQEffectiveSize");
				return;
			}
			
			if([packet isRxQ])
			{
				DDLogError(@"PseudoTcp: maybeSendData: resend packet with isRxQ == YES");
				return;
			}
			
			[self resendPacket:packet];
		}
		else
		{
			// Send NEW data
			
			// Create empty packet
			packet = [[[PseudoTcpPacket alloc] init] autorelease];
			[packet setSequence:[self sendNext]];
			
			NSMutableData *packetData = [NSMutableData dataWithCapacity:maxPacketDataLength];
			
			// The sendBuffer is an array of NSData objects.
			// We'll need to loop through this array, and fill the packetData to capacity.
			// This may require using more than one object in the sendBuffer,
			// and it may require using fragments of objects in the sendBuffer.
			
			while([packetData length] < maxPacketDataLength)
			{
				NSData *data = [sendBuffer objectAtIndex:0];
				
				// Determine how much data we can append to packetData.
				// This is the minimum of:
				// - The amount of unread data from the current data object.
				// - The amount of space left in packetData.
				UInt32 maxDataLength = MIN(([data length] - sendBufferOffset), (maxPacketDataLength - [packetData length]));
				
				const void *subData = [data bytes] + sendBufferOffset;
				[packetData appendBytes:subData length:maxDataLength];
				
				// Update the offset and size of the send buffer
				sendBufferOffset += maxDataLength;
				sendBufferSize -= maxDataLength;
				
				// If we've used up all the bytes in data, remove it from the send buffer
				if(sendBufferOffset == [data length])
				{
					sendSequence += sendBufferOffset;
					[sendBuffer removeObjectAtIndex:0];
					sendBufferOffset = 0;
				}
			}
			[packet setData:packetData];
			
			// Fear not - PseudoTcpPacket will not copy the packetData. It only retains it.
			
			[self maybeAddAck:packet];
			[self sendPacket:packet];
		}
		
		maxSendSize -= (UInt32)[[packet data] length];
	
	} // while(maxSendSize > 0)
}

/**
 * Immediately resends the packet in the retransmissionQueue with the given sequence number.
**/
- (void)resendPacketWithSequence:(UInt32)sequence
{
	NSUInteger i;
	for(i = 0; i < [retransmissionQueue count]; i++)
	{
		PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:i];
		
		if([packet sequence] == sequence)
		{
			[self resendPacket:packet];
			return;
		}
	}
}

/**
 * Schedules an empty window probe to be sent after the appropriate timeout, if not already scheduled.
**/
- (void)maybeScheduleEmptyWindowProbe
{
	// If the persistTimer is non-nil, then the empty window probe is already scheduled to be sent,
	// or has already been sent, and is still sitting in the retransmission queue.
	
	if(persistTimer == nil)
	{
		persistTimer = [[NSTimer timerWithTimeInterval:rto
												target:self
											  selector:@selector(doPersistTimeout:)
											  userInfo:nil
											   repeats:NO] retain];
		[self runLoopAddTimer:persistTimer];
		
		// Note: The persistTimer is invalidated and released in the processDataAck method.
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark RST
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Processes an incoming RST packet.
**/
- (void)processRst:(PseudoTcpPacket *)rstPacket
{
	// If there's data available in the recvBuffer, we don't want to close the socket until after
	// the data has been read by the upper-layer.
	if(recvBufferSize == 0)
	{
		// Update state
		state = STATE_CLOSED;
		
		// If we were still trying to send data, treat this as an error
		if(retransmissionQueueSize > 0 || sendBufferSize > 0)
		{
			if([delegate respondsToSelector:@selector(onPseudoTcp:willCloseWithError:)])
			{
				NSString *errMsg = @"Connection reset";
				NSDictionary *errInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
				
				NSError *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNRESET userInfo:errInfo];
				
				[delegate onPseudoTcp:self willCloseWithError:err];
			}
		}
		
		// Release TCP resources
		[self cleanup];
		
		// Notify delegate of closed socket
		if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
		{
			[delegate performSelector:@selector(onPseudoTcpDidClose:)
						   withObject:self
						   afterDelay:0.0
							  inModes:[udpSocket runLoopModes]];
		}
	}
	else
	{
		// We'll wait til all the data has been read before closing.
		// Remember: If the peer sent us a reset, we won't be able to send any more data to them.
		flags |= kConnectionReset;
		flags |= kForbidWrites;
		
		// What happens now?
		// The upper-layer will continue to be able to read data until they reach the end of the stream.
		// After they've read the last byte, the onPseudoTcp:willCloseWithError: and onPseudoTcpDidClose: methods
		// will be invoked.
	}
}

/**
 * If all queued data has been sent and acknowledged, sends the Rst packet.
**/
- (void)maybeSendRst
{
	if((sendBufferSize == 0) && (retransmissionQueueSize == 0))
	{
		// Create the RST packet
		PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] init] autorelease];
		[packet setIsRst:YES];
		
		[self sendPacket:packet];
		
		if(state != STATE_CLOSED)
		{
			// Update state
			state = STATE_CLOSED;
			
			// Release TCP resources
			[self cleanup];
			
			// Notify delegate of closed socket
			if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
			{
				[delegate performSelector:@selector(onPseudoTcpDidClose:)
							   withObject:self
							   afterDelay:0.0
								  inModes:[udpSocket runLoopModes]];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AsyncUdpSocket Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)onUdpSocket:(AsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
	DDLogVerbose(@"PseudoTcp: onUdpSocket:didSendDataWithTag:");
	
	// Update time of last packet sent/received
	[lastPacketTime release];
	lastPacketTime = [[NSDate date] retain];
	
	// Check to see if there's new data available for the delegate and, if so, inform them.
	// Note: We also check the recvBuffer as it's possible the delegate may have read
	// the data between when we received it, and when the ack finished sending.
	if((flags & kNewDataAvailable) && (recvBufferSize > 0))
	{
		if([delegate respondsToSelector:@selector(onPseudoTcpHasBytesAvailable:)])
		{
			[delegate onPseudoTcpHasBytesAvailable:self];
		}
		
		flags ^= kNewDataAvailable;
	}
}

- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
	DDLogError(@"PseudoTcp: onUdpSocket:didNotSendDataWithTag:dueToError:%@", error);
	
	if(state == STATE_CLOSED)
	{
		return;
	}
	
	// If something bad happens, such as the connection is refused, we'll receive a posix error.
	// We'll need to treat such a situation as an unrecoverable error.
	
	if([[error domain] isEqualToString:NSPOSIXErrorDomain])
	{
		// Error code is most likely ECONNREFUSED.
		// But really any posix error is likely unrecoverable.
		
		// Update state
		state = STATE_CLOSED;
		
		if([delegate respondsToSelector:@selector(onPseudoTcp:willCloseWithError:)])
		{
			[delegate onPseudoTcp:self willCloseWithError:error];
		}
		
		// Release TCP resources
		[self cleanup];
		
		if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
		{
			[delegate performSelector:@selector(onPseudoTcpDidClose:)
						   withObject:self
						   afterDelay:0.0
							  inModes:[udpSocket runLoopModes]];
		}
	}
}

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock
	 didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port
{
	// Update time of last packet sent/received
	[lastPacketTime release];
	lastPacketTime = [[NSDate date] retain];
	
	if(state == STATE_CLOSED)
	{
		// No longer receiving data
		return YES;
	}
	
	if([data length] < MIN_PSEUDO_TCP_PACKET_SIZE)
	{
		// Data isn't big enough to be a TCP packet
		return NO;
	}
	
	PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] initWithData:data] autorelease];
	
	DDLogInfo(@"PseudoTcp: RECV: flg(%d%d%d%d) seq(%010u) ack(%010u) wnd(%05u) dat(%03u)",
			  [packet isRst]  ? 1 : 0,
			  [packet isSack] ? 1 : 0,
			  [packet isAck]  ? 1 : 0,
			  [packet isSyn]  ? 1 : 0,
			  [packet sequence], [packet acknowledgement], [packet window], (unsigned)[[packet data] length]);
	
	if(state == STATE_LISTEN)
	{
		// We're waiting for a syn from the remote host
		if([packet isSyn])
		{
			// This could be a STUN validation packet that *looks* like a SYN packet at first glance.
			// But a true SYN packet would have an acknowledgement of zero.
			
			if([packet acknowledgement] == 0)
			{
				[self processOpeningSyn:packet];
			}
			else
			{
				DDLogWarn(@"PseudoTcp: Received non-syn is STATE_LISTEN [2]");
				return NO;
			}
		}
		else
		{
			DDLogWarn(@"PseudoTcp: Received non-syn is STATE_LISTEN [1]");
			return NO;
		}
	}
	else
	{
		if(state == STATE_SYN_SENT)
		{
			// We're waiting for a syn-ack from the remote host
			if([packet isSyn] && [packet isAck])
			{
				// This could be a STUN validation packet that *looks* like a SYN-ACK packet at first glance.
				// But a true SYN-ACK packet would have the proper acknowledgement number.
				
				if([packet acknowledgement] == sendSequence)
				{
					[self processOpeningSynAck:packet];
				}
				else
				{
					DDLogWarn(@"PseudoTcp: Received invalid packet in STATE_SYN_SENT [2]");
					return NO;
				}
			}
			else
			{
				DDLogWarn(@"PseudoTcp: Received invalid packet in STATE_SYN_SENT [1]");
				return NO;
			}
		}
		else if(state == STATE_SYN_RECEIVED)
		{
			// We're waiting for an ack to our syn-ack
			if([packet isAck])
			{
				// This could be a STUN validation packet that *looks* like an ACK packet at first glance.
				// But a true ACK packet would have the proper acknowledgement number.
				
				if([packet acknowledgement] == sendSequence)
				{
					[self processOpeningAck:packet];
				}
				else
				{
					DDLogWarn(@"PseudoTcp: Received invalid packet in STATE_SYN_RECEIVED [2]");
					return NO;
				}
			}
			else
			{
				DDLogWarn(@"PseudoTcp: Received invalid packet in STATE_SYN_RECEIVED [1]");
				return NO;
			}
		}
		else if(state == STATE_ESTABLISHED)
		{
			// We may still receive a syn-ack if our ack was lost
			if([packet isSyn] && [packet isAck])
			{
				// This could be a STUN validation packet that *looks* like a SYN-ACK packet at first glance.
				// But a duplicate SYN-ACK packet would have the same sequence number as before.
				
				if(([packet sequence] + 1) == recvSequence)
				{
					[self processOpeningSynAck:packet];
				}
				else
				{
					DDLogWarn(@"PseudoTcp: Received invalid duplicate SYN-ACK packet");
					return NO;
				}
			}
			else
			{
				if([packet isAck])
				{
					[self processDataAck:packet];
				}
				if([packet data])
				{
					[self processData:packet];
				}
				if([packet isRst])
				{
					[self processRst:packet];
				}
			}
		}
	}
	
	if(state != STATE_CLOSED)
	{
		[udpSocket receiveWithTimeout:NO_TIMEOUT tag:0];
	}
	
	return YES;
}

/**
 * Called if the socket is unable to receive data from the socket.
 * Since we don't use timeouts, this could only be due to an ICMP error, such as "connection refused".
 * We'll want to immediately handle such errors instead of waiting for a TCP timeout.
**/
- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotReceiveDataWithTag:(long)tag dueToError:(NSError *)error
{
	DDLogError(@"PseudoTcp: onUdpSocket:didNotReceiveDataWithTag:dueToError:%@", error);
	
	if(state == STATE_CLOSED)
	{
		return;
	}
	
	// If something bad happens, such as the connection is refused, we'll receive a posix error.
	// We'll need to treat such a situation as an unrecoverable error.
	
	if([[error domain] isEqualToString:NSPOSIXErrorDomain])
	{
		// Error code is most likely ECONNREFUSED.
		// But really any posix error is likely unrecoverable.
		
		// Update state
		state = STATE_CLOSED;
		
		if([delegate respondsToSelector:@selector(onPseudoTcp:willCloseWithError:)])
		{
			[delegate onPseudoTcp:self willCloseWithError:error];
		}
		
		// Release TCP resources
		[self cleanup];
		
		if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
		{
			[delegate performSelector:@selector(onPseudoTcpDidClose:)
						   withObject:self
						   afterDelay:0.0
							  inModes:[udpSocket runLoopModes]];
		}
	}
	else
	{
		// Some other unknown error occurred - continue reading from the socket
		[udpSocket receiveWithTimeout:NO_TIMEOUT tag:0];
	}
}

- (void)onUdpSocketDidClose:(AsyncUdpSocket *)sock
{
	DDLogError(@"PseudoTcp: onUdpSocketDidClose:");
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Timeouts
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when the timer for a packet in the retransmissionQueue expires.
**/
- (void)doTimeout:(NSTimer *)aTimer
{
	DDLogInfo(@"PseudoTcp: doTimeout: ---------------------------------------------------------");
	
	[retransmissionTimer release];
	retransmissionTimer = nil;
	
	// When the retransmission timer expires, do the following:
	// - Retransmit the earliest segment that has not been acknowledged
	// - Update RTO according to back-off rules
	// - Start the retransmission timer according to the updated RTO
	
	if([retransmissionQueue count] == 0)
	{
		DDLogError(@"PseudoTcp: retransmissionTimer fired with empty retransmissionQueue");
		return;
	}
	
	// Remember: The retransmission queue stores packets in sequence number order
	
	PseudoTcpPacket *packet = [retransmissionQueue objectAtIndex:0];
	
	// Update ssthresh and cwnd according to RFC 2581
	ssthresh = MAX((retransmissionQueueEffectiveSize / 2), (2 * DEFAULT_MTU));
	cwnd = DEFAULT_MTU;
	
	// Back-off RTO according to RFC 2988
	rto = rto * 2.0;
	if(rto > 60.0)
	{
		// We use a maximum value or 60 seconds for the RTO in accordance with section 2.5 of RFC 2988
		rto = 60.0;
	}
	
	// RFC 3782 says we should exit fast recovery now
	[self unsetRecover];
	lastAckCount = 0;
	
	// We either need to resend the packet, or we need to call it quits and terminate the TCP connection.
	// We can determine this based on how long we've been trying to send the packet.
	
	NSTimeInterval timeEllapsed = [[packet firstSent] timeIntervalSinceNow] * -1.0;
	
	// Note: Empty window probes should not cause timeouts, as long as we continue to receive responses to the probes.
	// Everytime we receive a response to a window probe, we update the firstSent timestamp of the packet.
	// Thus we shouldn't have to do anything special here concerning window probe packets.
	// And the back-off RTO above is appropriate for probes as well.
	
	if((timeEllapsed >= 0.0) && (timeEllapsed < 300.0))
	{
		BOOL isTimeout = NO;
		
		if([packet isSyn])
		{
			if(timeEllapsed >= SYN_TIMEOUT)
			{
				isTimeout = YES;
			}
		}
		else if(timeEllapsed >= DATA_TIMEOUT)
		{
			isTimeout = YES;
		}
		
		if(isTimeout)
		{
			// Update state
			state = STATE_CLOSED;
			
			if([delegate respondsToSelector:@selector(onPseudoTcp:willCloseWithError:)])
			{
				NSString *errMsg = @"Connection timed out";
				NSDictionary *errInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
				
				NSError *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:ETIMEDOUT userInfo:errInfo];
				
				[delegate onPseudoTcp:self willCloseWithError:err];
			}
			
			// Release TCP resources
			[self cleanup];
			
			if([delegate respondsToSelector:@selector(onPseudoTcpDidClose:)])
			{
				[delegate performSelector:@selector(onPseudoTcpDidClose:) 
							   withObject:self
							   afterDelay:0.0
								  inModes:[udpSocket runLoopModes]];
			}
			
			return;
		}
	}
	else
	{
		// The time interval doesn't appear to be accurate.
		// Maybe the user changed the clock, changed time zones, or daylight savings time kicked in.
		// We'll reset the pacekt's firstSent time so we can timeout eventually if needed.
		[packet setFirstSent:[NSDate date]];
		
		// Resetting the sent time of a packet in this situation won't interfere with the RTO calculation.
		// This is because retransmitted packets are not used to update the RTO.
		
		// How did we come up with the 300 seconds limit?
		// We use a maximum RTO of 60 seconds, and a maximum timeout of 3 minutes.
		// So it shouldn't be possible to ever encouter a valid elapsed time interval over 4 minutes.
	}
	
	// Mark all packets in the retransmission queue as needing to be resent
	
	retransmissionQueueEffectiveSize = 0;
	
	unsigned i;
	for(i = 0; i < [retransmissionQueue count]; i++)
	{
		[[retransmissionQueue objectAtIndex:i] setIsRxQ:NO];
	}
	
	// And immediately resend the oldest unacknowledged packet
	
	[self resendPacket:packet];
}

- (void)doAckTimeout:(NSTimer *)aTimer
{
	[self sendAckNow];
}

- (void)doPersistTimeout:(NSTimer *)aTimer
{
	DDLogInfo(@"PseudoTcp: doPersistTimeout");
	
	NSAssert(sendBufferSize > 0, @"Empty window probe scheduled when no data is available to be sent");
	
	// When the persist timer goes off, we create an empty window probe packet, and send it.
	// As long as the remote host continues to respond to the empty window probe,
	// we know the connection is still alive.
	// If the remote host responds with an ACK showing a non-empty window, we can continue sending data.
	// Otherwise, the remote host will send an ACK telling us their window size is still zero.
	// In this case, we'll update the sent timestamp of the empty window probe and allow it to timeout,
	// using the normal retransmission timer. Since we constantly update the sent timestamp
	// of the empty window probe, it will never cause the connection to be closed. That is, as long
	// as the remote host continues to respond to the probe, it will cause the RTO to increase, up to
	// the maximum value of 60 seconds. So the empty window probe will get resent after 1, 2, 4, 8, ... etc
	// up to every 60 seconds.
	
	PseudoTcpPacket *packet = [[[PseudoTcpPacket alloc] init] autorelease];
	[packet setSequence:[self sendNext]];
	[packet setIsEmptyWindowProbe:YES];
	
	// An empty window probe MUST (according to our specifications) contain a single byte of data
	
	NSMutableData *packetData = [NSMutableData dataWithCapacity:1];
	
	NSData *data = [sendBuffer objectAtIndex:0];
	
	const void *subData = [data bytes] + sendBufferOffset;
	[packetData appendBytes:subData length:1];
	
	// Update the offset and size of the send buffer
	sendBufferOffset += 1;
	sendBufferSize -= 1;
	
	// If we've used up all the bytes in data, remove it from the send buffer
	if(sendBufferOffset == [data length])
	{
		sendSequence += sendBufferOffset;
		[sendBuffer removeObjectAtIndex:0];
		sendBufferOffset = 0;
	}
	
	[packet setData:packetData];
	
	[self sendPacket:packet];
}

- (void)doKeepAliveTimeout:(NSTimer *)aTimer
{
	if(state == STATE_CLOSED)
	{
		[keepAliveTimer release];
		keepAliveTimer = nil;
		return;
	}
	
	NSTimeInterval ti = [lastPacketTime timeIntervalSinceNow] * -1.0;
	
	if((ti < 0) || (ti >= KEEP_ALIVE_TIMEOUT))
	{
		// Send some data to keep the UDP connection open.
		// This is required because the router will only maintain mappings for active UDP sockets.
		
		NSData *keepAliveData = [@"keep-alive" dataUsingEncoding:NSUTF8StringEncoding];
		
		// Note: The keepAliveData MUST be shorter than MIN_PSEUDO_TCP_PACKET_SIZE so as to be properly ignored
		
		[udpSocket sendData:keepAliveData withTimeout:NO_TIMEOUT tag:-1];
		
		// Update time of last packet sent/received
		[lastPacketTime release];
		lastPacketTime = [[NSDate date] retain];
		
		// Reschedule keep alive timer
		[keepAliveTimer release];
		keepAliveTimer = [[NSTimer timerWithTimeInterval:KEEP_ALIVE_TIMEOUT
												  target:self
												selector:@selector(doKeepAliveTimeout:)
												userInfo:nil
												 repeats:NO] retain];
		[self runLoopAddTimer:keepAliveTimer];
	}
	else
	{
		// Reschedule keep alive timer
		[keepAliveTimer release];
		keepAliveTimer = [[NSTimer timerWithTimeInterval:(KEEP_ALIVE_TIMEOUT - ti)
												  target:self
												selector:@selector(doKeepAliveTimeout:)
												userInfo:nil
												 repeats:NO] retain];
		[self runLoopAddTimer:keepAliveTimer];
	}
}

@end
