/**
 * Created by Robbie Hanson of Deusty, LLC.
 * This file is distributed under the GPL license.
 * Commercial licenses are available from deusty.com.
**/

#import "PseudoTcpPacket.h"
#import "DDNumber.h"


enum PseudoTcpPacketFlags
{
	TCP_FIN  =  1 << 0,
	TCP_SYN  =  1 << 1,
	TCP_RST  =  1 << 2,
	TCP_PSH  =  1 << 3,
	TCP_ACK  =  1 << 4,
	TCP_SACK =  1 << 5,
};

enum PseudoTcpPacketControlFlags
{
	CTRL_RXMIT = 1 << 0,  // Was the packet retransmitted, or is this the first time sending it.
	CTRL_PROBE = 1 << 1,  // Is this an empty window probe.
	CTRL_ISRXQ = 1 << 2,  // Is this packet part of the retransmissionQueueEffectiveSize
};


@implementation PseudoTcpPacket

- (id)initWithData:(NSData *)udpData
{
	if((self = [super init]))
	{
		if([udpData length] >= MIN_PSEUDO_TCP_PACKET_SIZE)
		{
			sequence         = [NSNumber extractUInt32FromData:udpData atOffset: 0 andConvertFromNetworkOrder:YES];
			acknowledgement  = [NSNumber extractUInt32FromData:udpData atOffset: 4 andConvertFromNetworkOrder:YES];
			
			control          = [NSNumber extractUInt8FromData:udpData atOffset:8];
			flags            = [NSNumber extractUInt8FromData:udpData atOffset:9];
			
			window           = [NSNumber extractUInt16FromData:udpData atOffset:10 andConvertFromNetworkOrder:YES];
			
			if([udpData length] > MIN_PSEUDO_TCP_PACKET_SIZE)
			{
				if(flags & TCP_SACK)
				{
					if([udpData length] >= MIN_PSEUDO_TCP_PACKET_SIZE + 4)
					{
						sackSequence = [NSNumber extractUInt32FromData:udpData
															  atOffset:12
											andConvertFromNetworkOrder:YES];
					}
					if([udpData length] > MIN_PSEUDO_TCP_PACKET_SIZE + 4)
					{
						void *dataBytes = (void *)([udpData bytes] + 16);
						data = [[NSData alloc] initWithBytes:dataBytes length:([udpData length] - 16)];
					}
				}
				else
				{
					void *dataBytes = (void *)([udpData bytes] + 12);
					data = [[NSData alloc] initWithBytes:dataBytes length:([udpData length] - 12)];
				}
			}
		}
	}
	return self;
}

- (id)init
{
	if((self = [super init]))
	{
		sequence         = 0;
		acknowledgement  = 0;
		control          = 0;
		flags            = 0;
		window           = 0;
		sackSequence     = 0;
	}
	return self;
}

- (void)dealloc
{
	[data release];
	[firstSent release];
	[super dealloc];
}

- (UInt32)sequence {
	return sequence;
}
- (void)setSequence:(UInt32)num {
	sequence = num;
}

- (UInt32)acknowledgement {
	return acknowledgement;
}
- (void)setAcknowledgement:(UInt32)num {
	acknowledgement = num;
}

- (UInt16)window {
	return window;
}
- (void)setWindow:(UInt16)num {
	window = num;
}

- (BOOL)isSyn {
	return (flags & TCP_SYN);
}
- (void)setIsSyn:(BOOL)flag
{
	if(flag)
		flags |= TCP_SYN;
	else
		flags &= ~TCP_SYN;
}

- (BOOL)isAck {
	return (flags & TCP_ACK);
}
- (void)setIsAck:(BOOL)flag
{
	if(flag)
		flags |= TCP_ACK;
	else
		flags &= ~TCP_ACK;
}

- (BOOL)isRst {
	return (flags & TCP_RST);
}
- (void)setIsRst:(BOOL)flag
{
	if(flag)
		flags |= TCP_RST;
	else
		flags &= ~TCP_RST;
}

- (BOOL)isSack {
	return (flags & TCP_SACK);
}
- (void)setIsSack:(BOOL)flag
{
	if(flag)
		flags |= TCP_SACK;
	else
		flags &= ~TCP_SACK;
}

- (UInt32)sackSequence {
	return sackSequence;
}
- (void)setSackSequence:(UInt32)num {
	sackSequence = num;
}

- (NSData *)data {
	return data;
}
- (void)setData:(NSData *)payload
{
	if(data != payload)
	{
		[data release];
		data = [payload retain]; // Retain, do NOT copy
		
		// Note: Do NOT copy the given data!!!
		// When we generate the data objects from the send buffer, we create NSMutableData objects and copy the
		// appropriate bytes into the mutable object.  If we perform a copy at this point, we'll be copying the
		// bytes all over again just so we can store them in an immutable NSData object.  There's no need to do this,
		// as after we set the data, the PseudoTcpPacket is the only object with a reference to the data.
	}
}

- (NSData *)packetData
{
	// If we create an NSMutableData object here, then it will get copied when it gets sent to AsyncUdpSocket.
	// Since we know the size of the packet we're creating, we can easily create an NSData object instead.
	
	UInt16 dataLength = [data length];
	UInt16 optionsLength = [self isSack] ? 4 : 0;
	
	UInt32 packetSize = PSEUDO_TCP_HEADER_SIZE + optionsLength + dataLength;
	void *byteBuffer = malloc(packetSize);
	
	UInt32 seq = htonl(sequence);
	memcpy(byteBuffer+0, &seq, sizeof(seq));
	
	UInt32 ack = htonl(acknowledgement);
	memcpy(byteBuffer+4, &ack, sizeof(ack));
	
	// Remember: control bits are for internal use only
	
	UInt8 zero = 0;
	memcpy(byteBuffer+8, &zero, sizeof(zero));
	memcpy(byteBuffer+9, &flags, sizeof(flags));
	
	UInt16 wnd = htons(window);
	memcpy(byteBuffer+10, &wnd, sizeof(wnd));
	
	if([self isSack])
	{
		UInt32 sak = htonl(sackSequence);
		memcpy(byteBuffer+12, &sak, sizeof(sak));
		
		if(data)
		{
			memcpy(byteBuffer+16, [data bytes], dataLength);
		}
	}
	else
	{
		if(data)
		{
			memcpy(byteBuffer+12, [data bytes], dataLength);
		}
	}
	
	return [NSData dataWithBytesNoCopy:byteBuffer length:packetSize freeWhenDone:YES];
}

- (NSDate *)firstSent {
	return firstSent;
}
- (void)setFirstSent:(NSDate *)date
{
	if(firstSent != date)
	{
		[firstSent release];
		firstSent = [date retain];
	}
}

- (BOOL)wasRetransmitted {
	return (control & CTRL_RXMIT);
}
- (void)setWasRetransmitted:(BOOL)flag
{
	if(flag)
		control |= CTRL_RXMIT;
	else
		control &= ~CTRL_RXMIT;
}

- (BOOL)isEmptyWindowProbe {
	return (control & CTRL_PROBE);
}
- (void)setIsEmptyWindowProbe:(BOOL)flag
{
	if(flag)
		control |= CTRL_PROBE;
	else
		control &= ~CTRL_PROBE;
}

- (BOOL)isRxQ {
	return (control & CTRL_ISRXQ);
}
- (void)setIsRxQ:(BOOL)flag
{
	if(flag)
		control |= CTRL_ISRXQ;
	else
		control &= ~CTRL_ISRXQ;
}

@end
