/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import <Foundation/Foundation.h>

//    0                   1                   2                   3   
//    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//  0 |                        Sequence Number                        |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//  4 |                     Acknowledgment Number                     |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//    |               |   |S|A|P|R|S|F|                               |
//  8 |    Control    |   |A|C|S|S|Y|I|            Window             |
//    |               |   |K|K|H|T|N|N|                               |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// 12 |                             data                              |
//    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// 
// 
// Note: All numbers are in network order.

// The size of the Pseudo TCP header
#define PSEUDO_TCP_HEADER_SIZE  12

// The minimum size of a TCP packet, which includes just the headers
#define MIN_PSEUDO_TCP_PACKET_SIZE    PSEUDO_TCP_HEADER_SIZE


@interface PseudoTcpPacket : NSObject
{
	UInt32 sequence;
	UInt32 acknowledgement;
	UInt8  control;
	UInt8  flags;
	UInt16 window;
	UInt32 sackSequence;
	
	NSData *data;
	
	NSDate *firstSent;
}

- (id)initWithData:(NSData *)udpData;
- (id)init;

- (UInt32)sequence;
- (void)setSequence:(UInt32)num;

- (UInt32)acknowledgement;
- (void)setAcknowledgement:(UInt32)num;

- (UInt16)window;
- (void)setWindow:(UInt16)num;

- (BOOL)isSyn;
- (void)setIsSyn:(BOOL)flag;

- (BOOL)isAck;
- (void)setIsAck:(BOOL)flag;

- (BOOL)isRst;
- (void)setIsRst:(BOOL)flag;

- (BOOL)isSack;
- (void)setIsSack:(BOOL)flag;

- (UInt32)sackSequence;
- (void)setSackSequence:(UInt32)num;

- (NSData *)data;
- (void)setData:(NSData *)payload;

- (NSData *)packetData;

- (NSDate *)firstSent;
- (void)setFirstSent:(NSDate *)date;

- (BOOL)wasRetransmitted;
- (void)setWasRetransmitted:(BOOL)flag;

- (BOOL)isEmptyWindowProbe;
- (void)setIsEmptyWindowProbe:(BOOL)flag;

- (BOOL)isRxQ;
- (void)setIsRxQ:(BOOL)flag;

@end
