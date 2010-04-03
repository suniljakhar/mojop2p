/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "PseudoAsyncSocket.h"
#import "PseudoTcp.h"
#import "AsyncSocket.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 2
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#define DEFAULT_PREBUFFERING YES        // Whether pre-buffering is enabled by default

#define READQUEUE_CAPACITY	5           // Initial capacity
#define WRITEQUEUE_CAPACITY 5           // Initial capacity
#define READALL_CHUNKSIZE	256         // Incremental increase in buffer size
#define WRITE_CHUNKSIZE    (1024 * 16)  // Limit on size of each write pass

#define AsyncReadPacket  PseudoAsyncReadPacket
#define AsyncWritePacket PseudoAsyncWritePacket

enum AsyncSocketFlags
{
	kEnablePreBuffering     = 1 << 0,  // If set, pre-buffering is enabled
	kForbidReadsWrites      = 1 << 1,  // If set, no new reads or writes are allowed
	kDisconnectAfterReads   = 1 << 2,  // If set, disconnect after no more reads are queued
	kDisconnectAfterWrites  = 1 << 3,  // If set, disconnect after no more writes are queued
	kClosingWithError       = 1 << 4,  // If set, the socket is being closed due to an error
	kClosing                = 1 << 5,  // If set, the socket is being closed
	kClosed                 = 1 << 6,  // If set, the socket is closed
	kDequeueReadScheduled   = 1 << 7,  // If set, a maybeDequeueRead operation is already scheduled
	kDequeueWriteScheduled  = 1 << 8,  // If set, a maybeDequeueWrite operation is already scheduled
};

@interface PseudoAsyncSocket (Private)

// Disconnect Implementation
- (void)closeWithError:(NSError *)err;
- (void)recoverUnreadData;
- (void)emptyQueues;
- (void)close;

// Errors
- (NSError *)getReadMaxedOutError;
- (NSError *)getReadTimeoutError;
- (NSError *)getWriteTimeoutError;
- (NSError *)getMethodNotImplementedError;

// Reading
- (void)doBytesAvailable;
- (void)completeCurrentRead;
- (void)endCurrentRead;
- (void)scheduleDequeueRead;
- (void)maybeDequeueRead;
- (void)doReadTimeout:(NSTimer *)timer;

// Writing
- (void)doSendBytes;
- (void)completeCurrentWrite;
- (void)endCurrentWrite;
- (void)scheduleDequeueWrite;
- (void)maybeDequeueWrite;
- (void)maybeScheduleDisconnect;
- (void)doWriteTimeout:(NSTimer *)timer;

// Run Loop
- (void)runLoopAddTimer:(NSTimer *)timer;
- (void)runLoopRemoveTimer:(NSTimer *)timer;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The AsyncReadPacket encompasses the instructions for any given read.
 * The content of a read packet allows the code to determine if we're:
 *  - reading to a certain length
 *  - reading to a certain separator
 *  - or simply reading the first chunk of available data
**/
@interface AsyncReadPacket : NSObject
{
  @public
	NSMutableData *buffer;
	CFIndex bytesDone;
	NSTimeInterval timeout;
	CFIndex maxLength;
	long tag;
	NSData *term;
	BOOL readAllAvailableData;
}
- (id)initWithData:(NSMutableData *)d
		   timeout:(NSTimeInterval)t
			   tag:(long)i
  readAllAvailable:(BOOL)a
		terminator:(NSData *)e
	  	 maxLength:(CFIndex)m;

- (unsigned)readLengthForTerm;

- (unsigned)prebufferReadLengthForTerm;
- (CFIndex)searchForTermAfterPreBuffering:(CFIndex)numBytes;
@end

@implementation AsyncReadPacket

- (id)initWithData:(NSMutableData *)d
		   timeout:(NSTimeInterval)t
			   tag:(long)i
  readAllAvailable:(BOOL)a
		terminator:(NSData *)e
         maxLength:(CFIndex)m
{
	if((self = [super init]))
	{
		buffer = [d retain];
		timeout = t;
		tag = i;
		readAllAvailableData = a;
		term = [e copy];
		bytesDone = 0;
		maxLength = m;
	}
	return self;
}

/**
 * For read packets with a set terminator, returns the safe length of data that can be read
 * without going over a terminator, or the maxLength.
 * 
 * It is assumed the terminator has not already been read.
**/
- (unsigned)readLengthForTerm
{
	NSAssert(term != nil, @"Searching for term in data when there is no term.");
	
	// What we're going to do is look for a partial sequence of the terminator at the end of the buffer.
	// If a partial sequence occurs, then we must assume the next bytes to arrive will be the rest of the term,
	// and we can only read that amount.
	// Otherwise, we're safe to read the entire length of the term.
	
	unsigned result = [term length];
	
	// Shortcut when term is a single byte
	if(result == 1) return result;
	
	// i = index within buffer at which to check data
	// j = length of term to check against
	
	// Note: Beware of implicit casting rules
	// This could give you -1: MAX(0, (0 - [term length] + 1));
	
	CFIndex i = MAX(0, (CFIndex)(bytesDone - [term length] + 1));
	CFIndex j = MIN([term length] - 1, bytesDone);
	
	while(i < bytesDone)
	{
		const void *subBuffer = [buffer bytes] + i;
		
		if(memcmp(subBuffer, [term bytes], j) == 0)
		{
			result = [term length] - j;
			break;
		}
		
		i++;
		j--;
	}
	
	if(maxLength > 0)
		return MIN(result, (maxLength - bytesDone));
	else
		return result;
}

/**
 * Assuming pre-buffering is enabled, returns the amount of data that can be read
 * without going over the maxLength.
**/
- (unsigned)prebufferReadLengthForTerm
{
	if(maxLength > 0)
		return MIN(READALL_CHUNKSIZE, (maxLength - bytesDone));
	else
		return READALL_CHUNKSIZE;
}

/**
 * For read packets with a set terminator, scans the packet buffer for the term.
 * It is assumed the terminator had not been fully read prior to the new bytes.
 * 
 * If the term is found, the number of excess bytes after the term are returned.
 * If the term is not found, this method will return -1.
 * 
 * Note: A return value of zero means the term was found at the very end.
**/
- (CFIndex)searchForTermAfterPreBuffering:(CFIndex)numBytes
{
	NSAssert(term != nil, @"Searching for term in data when there is no term.");
	
	// We try to start the search such that the first new byte read matches up with the last byte of the term.
	// We continue searching forward after this until the term no longer fits into the buffer.
	
	// Note: Beware of implicit casting rules
	// This could give you -1: MAX(0, 1 - 1 - [term length] + 1);
	
	CFIndex i = MAX(0, (CFIndex)(bytesDone - numBytes - [term length] + 1));
	
	while(i + [term length] <= bytesDone)
	{
		const void *subBuffer = [buffer bytes] + i;
		
		if(memcmp(subBuffer, [term bytes], [term length]) == 0)
		{
			return bytesDone - (i + [term length]);
		}
		
		i++;
	}
	
	return -1;
}

- (void)dealloc
{
	[buffer release];
	[term release];
	[super dealloc];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The AsyncWritePacket encompasses the instructions for any given write.
**/
@interface AsyncWritePacket : NSObject
{
  @public
	NSData *buffer;
	CFIndex bytesDone;
	long tag;
	NSTimeInterval timeout;
}
- (id)initWithData:(NSData *)d timeout:(NSTimeInterval)t tag:(long)i;
@end

@implementation AsyncWritePacket

- (id)initWithData:(NSData *)d timeout:(NSTimeInterval)t tag:(long)i
{
	if((self = [super init]))
	{
		buffer = [d retain];
		timeout = t;
		tag = i;
		bytesDone = 0;
	}
	return self;
}

- (void)dealloc
{
	[buffer release];
	[super dealloc];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation PseudoAsyncSocket

- (id)initWithPseudoTcp:(PseudoTcp *)socket
{
	if((self = [super init]))
	{
		pseudoSocket = [socket retain];
		[pseudoSocket setDelegate:self];
		
		theFlags = DEFAULT_PREBUFFERING ? kEnablePreBuffering : 0;
		theUserData = 0;
		
		theReadQueue = [[NSMutableArray alloc] initWithCapacity:READQUEUE_CAPACITY];
		theCurrentRead = nil;
		theReadTimer = nil;
		
		partialReadBuffer = [[NSMutableData alloc] initWithCapacity:READALL_CHUNKSIZE];
		
		theWriteQueue = [[NSMutableArray alloc] initWithCapacity:WRITEQUEUE_CAPACITY];
		theCurrentWrite = nil;
		theWriteTimer = nil;
	}
	return self;
}

- (void)dealloc
{
	DDLogInfo(@"Destroying %@", self);
	
	[self close];
	[theReadQueue release];
	[theWriteQueue release];
	[NSObject cancelPreviousPerformRequestsWithTarget:theDelegate selector:@selector(onSocketDidDisconnect:) object:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	
	if([pseudoSocket delegate] == self)
	{
		[pseudoSocket setDelegate:nil];
	}
	[pseudoSocket release];
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (long)userData
{
	return theUserData;
}

- (void)setUserData:(long)userData
{
	theUserData = userData;
}

- (id)delegate
{
	return theDelegate;
}

- (void)setDelegate:(id)delegate
{
	theDelegate = delegate;
}

- (BOOL)canSafelySetDelegate
{
	return ([theReadQueue count] == 0 && [theWriteQueue count] == 0 && theCurrentRead == nil && theCurrentWrite == nil);
}

- (CFSocketRef)getCFSocket
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: getCFSocket");
	return NULL;
}

- (CFReadStreamRef)getCFReadStream
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: getCFReadStream");
	return NULL;
}

- (CFWriteStreamRef)getCFWriteStream
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: getCFWriteStream");
	return NULL;
}

- (PseudoTcp *)getPseudoTcp
{
	return pseudoSocket;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Progress
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (float)progressOfReadReturningTag:(long *)tag bytesDone:(CFIndex *)done total:(CFIndex *)total
{
	// Check to make sure we're actually reading something right now
	if (!theCurrentRead) return NAN;
	
	// It's only possible to know the progress of our read if we're reading to a certain length
	// If we're reading to data, we of course have no idea when the data will arrive
	// If we're reading to timeout, then we have no idea when the next chunk of data will arrive.
	BOOL hasTotal = (theCurrentRead->readAllAvailableData == NO && theCurrentRead->term == nil);
	
	CFIndex d = theCurrentRead->bytesDone;
	CFIndex t = hasTotal ? [theCurrentRead->buffer length] : 0;
	if (tag != NULL)   *tag = theCurrentRead->tag;
	if (done != NULL)  *done = d;
	if (total != NULL) *total = t;
	float ratio = (float)d/(float)t;
	return isnan(ratio) ? 1.0F : ratio; // 0 of 0 bytes is 100% done.
}

- (float)progressOfWriteReturningTag:(long *)tag bytesDone:(CFIndex *)done total:(CFIndex *)total
{
	if (!theCurrentWrite) return NAN;
	CFIndex d = theCurrentWrite->bytesDone;
	CFIndex t = [theCurrentWrite->buffer length];
	if (tag != NULL)   *tag = theCurrentWrite->tag;
	if (done != NULL)  *done = d;
	if (total != NULL) *total = t;
	return (float)d/(float)t;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Run Loop
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)runLoopAddTimer:(NSTimer *)timer
{
	CFRunLoopRef theRunLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	NSArray *theRunLoopModes = [pseudoSocket runLoopModes];
	unsigned i, count = [theRunLoopModes count];
	for(i = 0; i < count; i++)
	{
		CFStringRef runLoopMode = (CFStringRef)[theRunLoopModes objectAtIndex:i];
		CFRunLoopAddTimer(theRunLoop, (CFRunLoopTimerRef)timer, runLoopMode);
	}
}

- (void)runLoopRemoveTimer:(NSTimer *)timer
{
	CFRunLoopRef theRunLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	NSArray *theRunLoopModes = [pseudoSocket runLoopModes];
	unsigned i, count = [theRunLoopModes count];
	for(i = 0; i < count; i++)		
	{
		CFStringRef runLoopMode = (CFStringRef)[theRunLoopModes objectAtIndex:i];
		CFRunLoopRemoveTimer(theRunLoop, (CFRunLoopTimerRef)timer, runLoopMode);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See the header file for a full explanation of pre-buffering.
**/
- (void)enablePreBuffering
{
	theFlags |= kEnablePreBuffering;
}

/**
 * See the header file for a full explanation of this method.
**/
- (BOOL)moveToRunLoop:(NSRunLoop *)runLoop
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: moveToRunLoop:");
	
	return NO;
}

/**
 * See the header file for a full explanation of this method.
**/
- (BOOL)setRunLoopModes:(NSArray *)runLoopModes
{
	if([runLoopModes count] == 0)
	{
		return NO;
	}
	if([[pseudoSocket runLoopModes] isEqualToArray:runLoopModes])
	{
		return YES;
	}
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	theFlags &= ~kDequeueReadScheduled;
	theFlags &= ~kDequeueWriteScheduled;
	
	// We do not retain the timers - they get retained by the runloop when we add them as a source.
	// Since we're about to remove them as a source, we retain now, and release again below.
	[theReadTimer retain];
	[theWriteTimer retain];
	
	if(theReadTimer) [self runLoopRemoveTimer:theReadTimer];
	if(theWriteTimer) [self runLoopRemoveTimer:theWriteTimer];
	
	[pseudoSocket setRunLoopModes:runLoopModes];
	
	if(theReadTimer) [self runLoopAddTimer:theReadTimer];
	if(theWriteTimer) [self runLoopAddTimer:theWriteTimer];
	
	// Release timers since we retained them above
	[theReadTimer release];
	[theWriteTimer release];
	
	[self performSelector:@selector(maybeDequeueRead) withObject:nil afterDelay:0 inModes:runLoopModes];
	[self performSelector:@selector(maybeDequeueWrite) withObject:nil afterDelay:0 inModes:runLoopModes];
	[self performSelector:@selector(maybeScheduleDisconnect) withObject:nil afterDelay:0 inModes:runLoopModes];
	
	return YES;
}

- (NSArray *)runLoopModes
{
	return [pseudoSocket runLoopModes];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accepting
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)acceptOnPort:(UInt16)port error:(NSError **)errPtr
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: acceptOnPort:error:");
	
	if(errPtr) *errPtr = [self getMethodNotImplementedError];
	return NO;
}

- (BOOL)acceptOnAddress:(NSString *)hostaddr port:(UInt16)port error:(NSError **)errPtr
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: acceptOnAddress:port:error:");
	
	if(errPtr) *errPtr = [self getMethodNotImplementedError];
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connecting
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)connectToHost:(NSString *)hostname onPort:(UInt16)port error:(NSError **)errPtr
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: connectToHost:onPort:error:");
	
	if(errPtr) *errPtr = [self getMethodNotImplementedError];
	return NO;
}

- (BOOL)connectToAddress:(NSData *)remoteAddr error:(NSError **)errPtr
{
	DDLogWarn(@"PseudoAsyncSocket: Inoperable method called: connectToAddress:error:");
	
	if(errPtr) *errPtr = [self getMethodNotImplementedError];
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Disconnect Implementation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Sends error message and disconnects
- (void)closeWithError:(NSError *)err
{
	theFlags |= kClosingWithError;
	
	// Try to salvage what data we can.
	[self recoverUnreadData];
	
	// Let the delegate know, so it can try to recover if it likes.
	if ([theDelegate respondsToSelector:@selector(onSocket:willDisconnectWithError:)])
	{
		[theDelegate onSocket:self willDisconnectWithError:err];
	}
	
	[self close];
}

// Prepare partially read data for recovery.
- (void)recoverUnreadData
{
	if((theCurrentRead != nil) && (theCurrentRead->bytesDone > 0))
	{
		// We never finished the current read.
		// We need to move its data into the front of the partial read buffer.
		
		[partialReadBuffer replaceBytesInRange:NSMakeRange(0, 0)
									 withBytes:[theCurrentRead->buffer bytes]
										length:theCurrentRead->bytesDone];
	}
	
	[self emptyQueues];
}

- (void)emptyQueues
{
	if (theCurrentRead != nil)	[self endCurrentRead];
	if (theCurrentWrite != nil)	[self endCurrentWrite];
	
	[theReadQueue removeAllObjects];
	[theWriteQueue removeAllObjects];
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(maybeDequeueRead) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(maybeDequeueWrite) object:nil];
	
	theFlags &= ~kDequeueReadScheduled;
	theFlags &= ~kDequeueWriteScheduled;
}

/**
 * Disconnects. This is called for both error and clean disconnections.
**/
- (void)close
{
	theFlags |= kClosing;
	
	// Empty queues
	[self emptyQueues];
	
	// Clear partialReadBuffer (pre-buffer and also unreadData buffer in case of error)
	[partialReadBuffer replaceBytesInRange:NSMakeRange(0, [partialReadBuffer length]) withBytes:NULL length:0];
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(disconnect) object:nil];
	
	// Just because we wrote data to the PseudoTcp socket does NOT mean the data has actually been sent.
	// The data has only been inserted into the internal write buffer.
	// This is something we can typically forget about due to kernel space sockets.
	// We need to be more careful when dealing with user space sockets.
	[pseudoSocket closeAfterWriting];
}

/**
 * Disconnects immediately. Any pending reads or writes are dropped.
**/
- (void)disconnect
{
	[self close];
}

/**
 * Diconnects after all pending reads have completed.
**/
- (void)disconnectAfterReading
{
	theFlags |= (kForbidReadsWrites | kDisconnectAfterReads);
	
	[self maybeScheduleDisconnect];
}

/**
 * Disconnects after all pending writes have completed.
**/
- (void)disconnectAfterWriting
{
	theFlags |= (kForbidReadsWrites | kDisconnectAfterWrites);
	
	[self maybeScheduleDisconnect];
}

/**
 * Disconnects after all pending reads and writes have completed.
**/
- (void)disconnectAfterReadingAndWriting
{
	theFlags |= (kForbidReadsWrites | kDisconnectAfterReads | kDisconnectAfterWrites);
	
	[self maybeScheduleDisconnect];
}

/**
 * Schedules a call to disconnect if possible.
 * That is, if all writes have completed, and we're set to disconnect after writing,
 * or if all reads have completed, and we're set to disconnect after reading.
**/
- (void)maybeScheduleDisconnect
{
	BOOL shouldDisconnect = NO;
	
	if(theFlags & kDisconnectAfterReads)
	{
		if(([theReadQueue count] == 0) && (theCurrentRead == nil))
		{
			if(theFlags & kDisconnectAfterWrites)
			{
				if(([theWriteQueue count] == 0) && (theCurrentWrite == nil))
				{
					shouldDisconnect = YES;
				}
			}
			else
			{
				shouldDisconnect = YES;
			}
		}
	}
	else if(theFlags & kDisconnectAfterWrites)
	{
		if(([theWriteQueue count] == 0) && (theCurrentWrite == nil))
		{
			shouldDisconnect = YES;
		}
	}
	
	if(shouldDisconnect)
	{
		[self performSelector:@selector(disconnect)
				   withObject:nil
				   afterDelay:0.0
					  inModes:[pseudoSocket runLoopModes]];
	}
}

/**
 * In the event of an error, this method may be called during onSocket:willDisconnectWithError: to read
 * any data that's left on the socket.
**/
- (NSData *)unreadData
{
	// Ensure this method will only return data in the event of an error
	if(!(theFlags & kClosingWithError)) return nil;
	
	CFIndex totalBytesRead = [partialReadBuffer length];
	BOOL error = NO;
	while(!error && [pseudoSocket hasBytesAvailable])
	{
		[partialReadBuffer increaseLengthBy:READALL_CHUNKSIZE];
		
		// Number of bytes to read is space left in packet buffer.
		CFIndex bytesToRead = [partialReadBuffer length] - totalBytesRead;
		
		// Read data into packet buffer
		UInt8 *packetbuf = (UInt8 *)( [partialReadBuffer mutableBytes] + totalBytesRead );
		CFIndex bytesRead = [pseudoSocket read:packetbuf maxLength:bytesToRead];
		
		// Check results
		if(bytesRead < 0)
		{
			error = YES;
		}
		else
		{
			totalBytesRead += bytesRead;
		}
	}
	
	[partialReadBuffer setLength:totalBytesRead];
	
	return partialReadBuffer;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)getReadMaxedOutError
{
	NSString *errMsg = NSLocalizedStringWithDefaultValue(@"AsyncSocketReadMaxedOutError",
														 @"AsyncSocket", [NSBundle mainBundle],
														 @"Read operation reached set maximum length", nil);
	
	NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
	
	return [NSError errorWithDomain:AsyncSocketErrorDomain code:AsyncSocketReadMaxedOutError userInfo:info];
}

/**
 * Returns a standard AsyncSocket read timeout error.
**/
- (NSError *)getReadTimeoutError
{
	NSString *errMsg = NSLocalizedStringWithDefaultValue(@"AsyncSocketReadTimeoutError",
														 @"AsyncSocket", [NSBundle mainBundle],
														 @"Read operation timed out", nil);
	
	NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
	
	return [NSError errorWithDomain:AsyncSocketErrorDomain code:AsyncSocketReadTimeoutError userInfo:info];
}

/**
 * Returns a standard AsyncSocket write timeout error.
**/
- (NSError *)getWriteTimeoutError
{
	NSString *errMsg = NSLocalizedStringWithDefaultValue(@"AsyncSocketWriteTimeoutError",
														 @"AsyncSocket", [NSBundle mainBundle],
														 @"Write operation timed out", nil);
	
	NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
	
	return [NSError errorWithDomain:AsyncSocketErrorDomain code:AsyncSocketWriteTimeoutError userInfo:info];
}

- (NSError *)getMethodNotImplementedError
{
	NSString *errMsg = NSLocalizedStringWithDefaultValue(@"AsyncSocketMethodNotImplementedError",
	                                                     @"AsyncSocket", [NSBundle mainBundle],
	                                                     @"Method not implemented", nil);
	
	NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
	
	return [NSError errorWithDomain:AsyncSocketErrorDomain code:AsyncSocketNoError userInfo:info];
}

- (NSError *)getConnectionResetError
{
	NSString *errMsg = @"Connection reset";
	NSDictionary *errInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
	
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNRESET userInfo:errInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Diagnostics
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isConnected
{
	return (!(theFlags & kClosed));
}

- (NSString *)connectedHost
{
	return [[pseudoSocket udpSocket] connectedHost];
}

- (UInt16)connectedPort
{
	return [[pseudoSocket udpSocket] connectedPort];
}

- (NSString *)localHost
{
	return [[pseudoSocket udpSocket] localHost];
}

- (UInt16)localPort
{
	return [[pseudoSocket udpSocket] localPort];
}

- (BOOL)isIPv4
{
	return YES;
}

- (BOOL)isIPv6
{
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Reading
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)readDataToLength:(CFIndex)length withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
	DDLogInfo(@"PseudoAsyncSocket: readDataToLength:%i withTimeout:%f tag:%d", length, timeout, tag);
	
	if(length == 0) return;
	if(theFlags & kForbidReadsWrites) return;
	
	NSMutableData *buffer = [[NSMutableData alloc] initWithLength:length];
	AsyncReadPacket *packet = [[AsyncReadPacket alloc] initWithData:buffer
															timeout:timeout
																tag:tag
												   readAllAvailable:NO
														 terminator:nil
														  maxLength:length];

	[theReadQueue addObject:packet];
	[self scheduleDequeueRead];

	[packet release];
	[buffer release];
}

- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
	[self readDataToData:data withTimeout:timeout maxLength:-1 tag:tag];
}

- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout maxLength:(CFIndex)length tag:(long)tag
{
	DDLogInfo(@"PseudoAsyncSocket: readDataToData:(length=%u) withTimeout:%f maxLength:%i tag:%d",
			  [data length], timeout, length, tag);
	
	if(data == nil || [data length] == 0) return;
	if(length >= 0 && length < [data length]) return;
	if(theFlags & kForbidReadsWrites) return;
	
	NSMutableData *buffer = [[NSMutableData alloc] initWithLength:0];
	AsyncReadPacket *packet = [[AsyncReadPacket alloc] initWithData:buffer
															timeout:timeout
																tag:tag 
												   readAllAvailable:NO 
														 terminator:data
														  maxLength:length];
	
	[theReadQueue addObject:packet];
	[self scheduleDequeueRead];
	
	[packet release];
	[buffer release];
}

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag
{
	DDLogInfo(@"PseudoAsyncSocket: readDataWithTimeout:%f tag:%d", timeout, tag);
	
	if (theFlags & kForbidReadsWrites) return;
	
	NSMutableData *buffer = [[NSMutableData alloc] initWithLength:0];
	AsyncReadPacket *packet = [[AsyncReadPacket alloc] initWithData:buffer
															timeout:timeout
																tag:tag
												   readAllAvailable:YES
														 terminator:nil
														  maxLength:-1];
	
	[theReadQueue addObject:packet];
	[self scheduleDequeueRead];
	
	[packet release];
	[buffer release];
}

/**
 * Puts a maybeDequeueRead on the run loop. 
 * An assumption here is that selectors will be performed consecutively within their priority.
**/
- (void)scheduleDequeueRead
{
	if((theFlags & kDequeueReadScheduled) == 0)
	{
		[self performSelector:@selector(maybeDequeueRead)
				   withObject:nil
				   afterDelay:0.0
					  inModes:[pseudoSocket runLoopModes]];
	}
}

/**
 * This method starts a new read, if needed.
 * It is called when a user requests a read,
 * or when a stream opens that may have requested reads sitting in the queue, etc.
**/
- (void)maybeDequeueRead
{
	// Unset the flag indicating a call to this method is scheduled
	theFlags &= ~kDequeueReadScheduled;
	
	// If we're not currently processing a read
	if(theCurrentRead == nil)
	{
		if([theReadQueue count] > 0)
		{
			// Dequeue the next object in the write queue
			theCurrentRead = [[theReadQueue objectAtIndex:0] retain];
			[theReadQueue removeObjectAtIndex:0];
	
			// Start time-out timer.
			if(theCurrentRead->timeout >= 0.0)
			{
				theReadTimer = [NSTimer timerWithTimeInterval:theCurrentRead->timeout
													   target:self 
													 selector:@selector(doReadTimeout:)
													 userInfo:nil
													  repeats:NO];
				[self runLoopAddTimer:theReadTimer];
			}
	
			// Immediately read, if possible
			[self doBytesAvailable];
		}
		else if(theFlags & kDisconnectAfterReads)
		{
			if(theFlags & kDisconnectAfterWrites)
			{
				if(([theWriteQueue count] == 0) && (theCurrentWrite == nil))
				{
					[self disconnect];
				}
			}
			else
			{
				[self disconnect];
			}
		}
	}
}

/**
 * Call this method in doBytesAvailable instead of CFReadStreamHasBytesAvailable().
 * This method supports pre-buffering properly.
**/
- (BOOL)hasBytesAvailable
{
	return ([partialReadBuffer length] > 0) || [pseudoSocket hasBytesAvailable];
}

/**
 * Call this method in doBytesAvailable instead of CFReadStreamRead().
 * This method support pre-buffering properly.
**/
- (CFIndex)readIntoBuffer:(UInt8 *)buffer maxLength:(CFIndex)length
{
	if([partialReadBuffer length] > 0)
	{
		// Determine the maximum amount of data to read
		CFIndex bytesToRead = MIN(length, [partialReadBuffer length]);
		
		// Copy the bytes from the buffer
		memcpy(buffer, [partialReadBuffer bytes], bytesToRead);
		
		// Remove the copied bytes from the buffer
		[partialReadBuffer replaceBytesInRange:NSMakeRange(0, bytesToRead) withBytes:NULL length:0];
		
		return bytesToRead;
	}
	else
	{
		return [pseudoSocket read:buffer maxLength:length];
	}
}

/**
 * This method is called when a new read is taken from the read queue or when new data becomes available on the stream.
**/
- (void)doBytesAvailable
{
	// If data is available on the stream, but there is no read request, then we don't need to process the data yet.
	if(theCurrentRead != nil)
	{
		CFIndex totalBytesRead = 0;
		
		BOOL done = NO;
		BOOL maxoutError = NO;
		
		while(!done && !maxoutError && [self hasBytesAvailable])
		{
			BOOL didPreBuffer = NO;
			
			// If reading all available data, make sure there's room in the packet buffer.
			if(theCurrentRead->readAllAvailableData == YES)
			{
				// Make sure there is at least READALL_CHUNKSIZE bytes available.
				// We don't want to increase the buffer any more than this or we'll waste space.
				// With prebuffering it's possible to read in a small chunk on the first read.
				
				unsigned buffInc = READALL_CHUNKSIZE - ([theCurrentRead->buffer length] - theCurrentRead->bytesDone);
				[theCurrentRead->buffer increaseLengthBy:buffInc];
			}

			// If reading until data, we may only want to read a few bytes.
			// Just enough to ensure we don't go past our term or over our max limit.
			// Unless pre-buffering is enabled, in which case we may want to read in a larger chunk.
			if(theCurrentRead->term != nil)
			{
				// If we already have data pre-buffered, we obviously don't want to pre-buffer it again.
				// So in this case we'll just read as usual.
				
				if(([partialReadBuffer length] > 0) || !(theFlags & kEnablePreBuffering))
				{
					unsigned maxToRead = [theCurrentRead readLengthForTerm];
					
					unsigned bufInc = maxToRead - ([theCurrentRead->buffer length] - theCurrentRead->bytesDone);
					[theCurrentRead->buffer increaseLengthBy:bufInc];
				}
				else
				{
					didPreBuffer = YES;
					unsigned maxToRead = [theCurrentRead prebufferReadLengthForTerm];
					
					unsigned buffInc = maxToRead - ([theCurrentRead->buffer length] - theCurrentRead->bytesDone);
					[theCurrentRead->buffer increaseLengthBy:buffInc];

				}
			}
			
			// Number of bytes to read is space left in packet buffer.
			CFIndex bytesToRead = [theCurrentRead->buffer length] - theCurrentRead->bytesDone;
			
			// Read data into packet buffer
			UInt8 *subBuffer = (UInt8 *)([theCurrentRead->buffer mutableBytes] + theCurrentRead->bytesDone);
			CFIndex bytesRead = [self readIntoBuffer:subBuffer maxLength:bytesToRead];
			
			// Update total amound read for the current read
			theCurrentRead->bytesDone += bytesRead;
			
			// Update total amount read in this method invocation
			totalBytesRead += bytesRead;

			// Is packet done?
			if(theCurrentRead->readAllAvailableData != YES)
			{
				if(theCurrentRead->term != nil)
				{
					if(didPreBuffer)
					{
						// Search for the terminating sequence within the big chunk we just read.
						CFIndex overflow = [theCurrentRead searchForTermAfterPreBuffering:bytesRead];
						
						if(overflow > 0)
						{
							// Copy excess data into partialReadBuffer
							NSMutableData *buffer = theCurrentRead->buffer;
							const void *overflowBuffer = [buffer bytes] + theCurrentRead->bytesDone - overflow;
							
							[partialReadBuffer appendBytes:overflowBuffer length:overflow];
							
							// Update the bytesDone variable.
							// Note: The completeCurrentRead method will trim the buffer for us.
							theCurrentRead->bytesDone -= overflow;
						}
						
						done = (overflow >= 0);
					}
					else
					{
						// Search for the terminating sequence at the end of the buffer
						int termlen = [theCurrentRead->term length];
						if(theCurrentRead->bytesDone >= termlen)
						{
							const void *buf = [theCurrentRead->buffer bytes] + (theCurrentRead->bytesDone - termlen);
							const void *seq = [theCurrentRead->term bytes];
							done = (memcmp (buf, seq, termlen) == 0);
						}
					}
					
					if(!done && theCurrentRead->maxLength >= 0 && theCurrentRead->bytesDone >= theCurrentRead->maxLength)
					{
						// There's a set maxLength, and we've reached that maxLength without completing the read
						maxoutError = YES;
					}
				}
				else
				{
					// Done when (sized) buffer is full.
					done = ([theCurrentRead->buffer length] == theCurrentRead->bytesDone);
				}
			}
			// else readAllAvailable doesn't end until all readable is read.
		}
		
		if(theCurrentRead->readAllAvailableData && theCurrentRead->bytesDone > 0)
			done = YES;	// Ran out of bytes, so the "read-all-data" type packet is done

		if(done)
		{
			[self completeCurrentRead];
			[self scheduleDequeueRead];
		}
		else if(theCurrentRead->bytesDone > 0)
		{
			// We're not done with the readToLength or readToData yet, but we have read in some bytes
			if ([theDelegate respondsToSelector:@selector(onSocket:didReadPartialDataOfLength:tag:)])
			{
				[theDelegate onSocket:self didReadPartialDataOfLength:totalBytesRead tag:theCurrentRead->tag];
			}
		}

		if(maxoutError)
		{
			[self closeWithError:[self getReadMaxedOutError]];
			return;
		}
	}
}

// Ends current read and calls delegate.
- (void)completeCurrentRead
{
	NSAssert (theCurrentRead, @"Trying to complete current read when there is no current read.");
	
	[theCurrentRead->buffer setLength:theCurrentRead->bytesDone];
	if([theDelegate respondsToSelector:@selector(onSocket:didReadData:withTag:)])
	{
		[theDelegate onSocket:self didReadData:theCurrentRead->buffer withTag:theCurrentRead->tag];
	}
	
	if (theCurrentRead != nil) [self endCurrentRead]; // Caller may have disconnected.
}

// Ends current read.
- (void)endCurrentRead
{
	NSAssert (theCurrentRead, @"Trying to end current read when there is no current read.");
	
	[theReadTimer invalidate];
	theReadTimer = nil;
	
	[theCurrentRead release];
	theCurrentRead = nil;
}

- (void)doReadTimeout:(NSTimer *)timer
{
	if (theCurrentRead != nil)
	{
		[self endCurrentRead];
	}
	[self closeWithError:[self getReadTimeoutError]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Writing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;
{
	DDLogInfo(@"PseudoAsyncSocket: writeData:(length=%u) withTimeout:%f tag:%d", [data length], timeout, tag);
	
	if (data == nil || [data length] == 0) return;
	if (theFlags & kForbidReadsWrites) return;
	
	AsyncWritePacket *packet = [[AsyncWritePacket alloc] initWithData:data timeout:timeout tag:tag];
	
	[theWriteQueue addObject:packet];
	[self scheduleDequeueWrite];
	
	[packet release];
}

- (void)scheduleDequeueWrite
{
	if((theFlags & kDequeueWriteScheduled) == 0)
	{
		[self performSelector:@selector(maybeDequeueWrite)
				   withObject:nil
				   afterDelay:0.0
					  inModes:[pseudoSocket runLoopModes]];
	}
}

// Start a new write.
- (void)maybeDequeueWrite
{
	// Unset the flag indicating a call to this method is scheduled
	theFlags &= ~kDequeueWriteScheduled;
	
	if (theCurrentWrite == nil)
	{
		if([theWriteQueue count] > 0)
		{
			// Dequeue the next object in the write queue
			theCurrentWrite = [[theWriteQueue objectAtIndex:0] retain];
			[theWriteQueue removeObjectAtIndex:0];
			
			// Start time-out timer
			if (theCurrentWrite->timeout >= 0.0)
			{
				theWriteTimer = [NSTimer timerWithTimeInterval:theCurrentWrite->timeout
														target:self
													  selector:@selector(doWriteTimeout:)
													  userInfo:nil
													   repeats:NO];
				[self runLoopAddTimer:theWriteTimer];
			}
			
			// Immediately write, if possible
			[self doSendBytes];
		}
		else if(theFlags & kDisconnectAfterWrites)
		{
			if(theFlags & kDisconnectAfterReads)
			{
				if(([theReadQueue count] == 0) && (theCurrentRead == nil))
				{
					[self disconnect];
				}
			}
			else
			{
				[self disconnect];
			}
		}
	}
}

- (void)doSendBytes
{
	if (theCurrentWrite != nil)
	{
		BOOL done = NO;
		while (!done && [pseudoSocket canAcceptBytes])
		{
			// Figure out what to write.
			CFIndex bytesRemaining = [theCurrentWrite->buffer length] - theCurrentWrite->bytesDone;
			CFIndex bytesToWrite = (bytesRemaining < WRITE_CHUNKSIZE) ? bytesRemaining : WRITE_CHUNKSIZE;
			
			// Write.
			CFIndex bytesWritten = [pseudoSocket writeData:theCurrentWrite->buffer
												  atOffset:theCurrentWrite->bytesDone
											 withMaxLength:bytesToWrite];
			
			// Is packet done?
			theCurrentWrite->bytesDone += bytesWritten;
			done = ([theCurrentWrite->buffer length] == theCurrentWrite->bytesDone);
		}
		
		if(done)
		{
			[self completeCurrentWrite];
			[self scheduleDequeueWrite];
		}
	}
}

// Ends current write and calls delegate.
- (void)completeCurrentWrite
{
	NSAssert (theCurrentWrite, @"Trying to complete current write when there is no current write.");
	DDLogInfo(@"PseudoAsyncSocket: completeCurrentWrite");
	
	if ([theDelegate respondsToSelector:@selector(onSocket:didWriteDataWithTag:)])
	{
		[theDelegate onSocket:self didWriteDataWithTag:theCurrentWrite->tag];
	}
	
	if (theCurrentWrite != nil) [self endCurrentWrite]; // Caller may have disconnected.
}

// Ends current write.
- (void)endCurrentWrite
{
	NSAssert (theCurrentWrite, @"Trying to complete current write when there is no current write.");
	
	[theWriteTimer invalidate];
	theWriteTimer = nil;
	
	[theCurrentWrite release];
	theCurrentWrite = nil;
}

- (void)doWriteTimeout:(NSTimer *)timer
{
	if(theCurrentWrite != nil)
	{
		[self endCurrentWrite];
	}
	[self closeWithError:[self getWriteTimeoutError]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark PseudoTcp Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)onPseudoTcpDidOpen:(PseudoTcp *)sock
{
	if([theDelegate respondsToSelector:@selector(onSocket:didConnectToHost:port:)])
	{
		[theDelegate onSocket:self
			 didConnectToHost:[self connectedHost]
						 port:[self connectedPort]];
	}
}

- (void)onPseudoTcpHasBytesAvailable:(PseudoTcp *)sock
{
	// User doesn't expect to complete reads/writes after calling close
	if(!(theFlags & kClosing))
	{
		DDLogInfo(@"PseudoAsyncSocket: onPseudoTcpHasBytesAvailable:");
		[self doBytesAvailable];
	}
}

- (void)onPseudoTcpCanAcceptBytes:(PseudoTcp *)sock
{
	// User doesn't expect to complete reads/writes after calling close
	if(!(theFlags & kClosing))
	{
		DDLogInfo(@"PseudoAsyncSocket: onPseudoTcpCanAcceptBytes:");
		[self doSendBytes];
	}
}

- (void)onPseudoTcp:(PseudoTcp *)sock willCloseWithError:(NSError *)err
{
	DDLogInfo(@"PseudoAsyncSocket: onPseudoTcp:willCloseWithError:");
	[self closeWithError:err];
}

- (void)onPseudoTcpDidClose:(PseudoTcp *)sock
{
	DDLogInfo(@"PseudoAsyncSocket: onPseudoTcpDidClose:");
	
	theFlags |= kClosed;
	
	if(!(theFlags & kClosing))
	{
		// The close method was never called!
		// This is an unplanned disconnection!
		[self closeWithError:[self getConnectionResetError]];
	}
	
	if([theDelegate respondsToSelector:@selector(onSocketDidDisconnect:)])
	{
		[theDelegate onSocketDidDisconnect:self];
	}
}

@end
