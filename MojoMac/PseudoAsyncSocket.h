/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

@class PseudoTcp;
@class PseudoAsyncSocket;
@class PseudoAsyncReadPacket;
@class PseudoAsyncWritePacket;

@interface NSObject (PseudoAsyncSocketDelegate)

- (void)onSocket:(PseudoAsyncSocket *)sock willDisconnectWithError:(NSError *)err;

- (void)onSocketDidDisconnect:(PseudoAsyncSocket *)sock;

/**
 * Will only be called if the underlying PseudoTcp was not already connected.
 * This will depend on how and when the PseudoAsyncSocket instance was created.
**/
- (void)onSocket:(PseudoAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port;

- (void)onSocket:(PseudoAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag;

- (void)onSocket:(PseudoAsyncSocket *)sock didReadPartialDataOfLength:(CFIndex)partialLength tag:(long)tag;

- (void)onSocket:(PseudoAsyncSocket *)sock didWriteDataWithTag:(long)tag;

@end



@interface PseudoAsyncSocket : NSObject
{
	PseudoTcp *pseudoSocket;
	
	NSMutableArray *theReadQueue;
	PseudoAsyncReadPacket *theCurrentRead;
	NSTimer *theReadTimer;
	NSMutableData *partialReadBuffer;
	
	NSMutableArray *theWriteQueue;
	PseudoAsyncWritePacket *theCurrentWrite;
	NSTimer *theWriteTimer;
	
	id theDelegate;
	UInt16 theFlags;
	
	long theUserData;
}

- (id)initWithPseudoTcp:(PseudoTcp *)socket;

- (id)delegate;
- (BOOL)canSafelySetDelegate;
- (void)setDelegate:(id)delegate;

- (long)userData;
- (void)setUserData:(long)userData;

//- (CFSocketRef)getCFSocket;
//- (CFReadStreamRef)getCFReadStream;
//- (CFWriteStreamRef)getCFWriteStream;

- (PseudoTcp *)getPseudoTcp;

//- (BOOL)acceptOnPort:(UInt16)port error:(NSError **)errPtr;
//- (BOOL)acceptOnAddress:(NSString *)hostaddr port:(UInt16)port error:(NSError **)errPtr;
//- (BOOL)connectToHost:(NSString *)hostname onPort:(UInt16)port error:(NSError **)errPtr;
//- (BOOL)connectToAddress:(NSData *)remoteAddr error:(NSError **)errPtr;

- (void)disconnect;
- (void)disconnectAfterReading;
- (void)disconnectAfterWriting;
- (void)disconnectAfterReadingAndWriting;

- (BOOL)isConnected;

- (NSString *)connectedHost;
- (UInt16)connectedPort;

- (NSString *)localHost;
- (UInt16)localPort;

- (BOOL)isIPv4;
- (BOOL)isIPv6;

- (void)readDataToLength:(CFIndex)length withTimeout:(NSTimeInterval)timeout tag:(long)tag;

- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

- (void)readDataToData:(NSData *)data withTimeout:(NSTimeInterval)timeout maxLength:(CFIndex)length tag:(long)tag;

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag;

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

- (float)progressOfReadReturningTag:(long *)tag bytesDone:(CFIndex *)done total:(CFIndex *)total;
- (float)progressOfWriteReturningTag:(long *)tag bytesDone:(CFIndex *)done total:(CFIndex *)total;

- (void)enablePreBuffering;

- (BOOL)moveToRunLoop:(NSRunLoop *)runLoop;

- (BOOL)setRunLoopModes:(NSArray *)runLoopModes;
- (NSArray *)runLoopModes;

- (NSData *)unreadData;

@end
