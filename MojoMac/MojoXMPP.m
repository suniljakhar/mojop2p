#import "MojoXMPP.h"
#import "MojoDefinitions.h"


@implementation XMPPUser (MojoAdditions)

- (NSString *)mojoDisplayName
{
	return [self mojoDisplayName:[self primaryMojoResource]];
}

- (NSString *)mojoDisplayName:(XMPPResource *)resource
{
	NSString *nickname = [self nickname];
	if(nickname)
		return nickname;
	
	NSString *shareName = [resource shareName];
	if(shareName)
		return shareName;
	
	return [jid bare];
}

- (BOOL)hasMojoResource
{
	return ([[self unsortedMojoResources] count] > 0);
}

- (XMPPResource *)primaryMojoResource
{
	NSArray *sortedMojoResources = [self sortedMojoResources];
	
	if([sortedMojoResources count] > 0)
	{
		return (XMPPResource *)[sortedMojoResources objectAtIndex:0];
	}
	
	return nil;
}

- (XMPPResource *)resourceForLibraryID:(NSString *)libID
{
	NSArray *allResources = [self unsortedMojoResources];
	
	int i;
	for(i = 0; i < [allResources count]; i++)
	{
		XMPPResource *resource = [allResources objectAtIndex:i];
		
		if([libID isEqualToString:[resource libraryID]])
		{
			return resource;
		}
	}
	
	return nil;
}

- (NSArray *)sortedMojoResources
{
	NSArray *sortedResources = [self sortedResources];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[sortedResources count]];
	
	int i;
	for(i = 0; i < [sortedResources count]; i++)
	{
		XMPPResource *resource = [sortedResources objectAtIndex:i];
		if([resource isMojoResource])
		{
			[result addObject:resource];
		}
	}
	
	return result;
}

- (NSArray *)unsortedMojoResources
{
	NSArray *unsortedResources = [self unsortedResources];
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[unsortedResources count]];
	
	int i;
	for(i = 0; i < [unsortedResources count]; i++)
	{
		XMPPResource *resource = [unsortedResources objectAtIndex:i];
		if([resource isMojoResource])
		{
			[result addObject:resource];
		}
	}
	
	return result;
}

- (NSComparisonResult)compareByMojoName:(XMPPUser *)another
{
	return [self compareByMojoName:another options:0];
}

- (NSComparisonResult)compareByMojoName:(XMPPUser *)another options:(NSStringCompareOptions)mask
{
	NSString *myName = [self mojoDisplayName];
	NSString *theirName = [another mojoDisplayName];
	
	return [myName compare:theirName options:mask];
}

- (NSComparisonResult)compareByMojoAvailabilityName:(XMPPUser *)another
{
	return [self compareByMojoAvailabilityName:another options:0];
}

- (NSComparisonResult)compareByMojoAvailabilityName:(XMPPUser *)another options:(NSStringCompareOptions)mask
{
	if([self hasMojoResource])
	{
		if([another hasMojoResource])
			return [self compareByMojoName:another options:mask];
		else
			return NSOrderedAscending;
	}
	else
	{
		if([another hasMojoResource])
			return NSOrderedDescending;
		else
			return [self compareByMojoName:another options:mask];
	}
}

- (NSInteger)strictRosterOrder
{
	return [self tag];
}

- (NSComparisonResult)strictRosterOrderCompare:(XMPPUser *)aUser
{
	if([self strictRosterOrder] < [aUser strictRosterOrder]) return NSOrderedAscending;
	if([self strictRosterOrder] < [aUser strictRosterOrder]) return NSOrderedDescending;
	
	return NSOrderedSame;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPResource (MojoAdditions)

- (NSXMLElement *)txtRecordElement
{
	NSXMLElement *txtRecordElement= [presence elementForName:@"x" xmlns:@"mojo:x:txtrecord"];
	if(!txtRecordElement)
	{
		txtRecordElement = [presence elementForName:@"x" xmlns:@"maestro:x:txtrecord"];
	}
	return txtRecordElement;
}

- (BOOL)isMojoResource
{
	return ([self txtRecordElement] != nil);
}

- (NSString *)libraryID
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	return [[txtRecordElement elementForName:TXTRCD2_LIBRARY_ID] stringValue];
}

- (NSString *)shareName
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	return [[txtRecordElement elementForName:TXTRCD2_SHARE_NAME] stringValue];
}

- (BOOL)zlibSupport
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	NSString *temp = [[txtRecordElement elementForName:TXTRCD_ZLIB_SUPPORT] stringValue];
	return ([temp intValue] != 0);
}

- (BOOL)gzipSupport
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	NSString *temp = [[txtRecordElement elementForName:TXTRCD_GZIP_SUPPORT] stringValue];
	return ([temp intValue] != 0);
}

- (BOOL)requiresPassword
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	NSString *temp = [[txtRecordElement elementForName:TXTRCD_REQUIRES_PASSWORD] stringValue];
	return ([temp intValue] != 0);
}

- (BOOL)requiresTLS
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	NSString *temp = [[txtRecordElement elementForName:TXTRCD_REQUIRES_TLS] stringValue];
	return ([temp intValue] != 0);
}

- (BOOL)stuntSupport
{
	return ([self stuntVersion] > 0.0f);
}

- (BOOL)stunSupport
{
	return ([self stunVersion] > 0.0f);
}

- (BOOL)searchSupport
{
	return ([self searchVersion] > 0.0f);
}

- (float)stuntVersion
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	float result = [[[txtRecordElement elementForName:TXTRCD_STUNT_VERSION] stringValue] floatValue];
	
	// Note: STUNT support is mandatory in all Mojo clients, so we can assume it's at least version 1.0.
	// This check is required because we didn't always include the stunt version in the txt record.
	
	if(result > 0.0f)
		return result;
	else
		return 1.0f;
}

- (float)stunVersion
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	return [[[txtRecordElement elementForName:TXTRCD_STUN_VERSION] stringValue] floatValue];
}

- (float)searchVersion
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	return [[[txtRecordElement elementForName:TXTRCD_SEARCH_VERSION] stringValue] floatValue];
}

- (int)numSongs
{
	NSXMLElement *txtRecordElement = [self txtRecordElement];
	
	return [[[txtRecordElement elementForName:TXTRCD2_NUM_SONGS] stringValue] intValue];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPUserAndMojoResource

- (id)initWithUser:(XMPPUser *)aUser resource:(XMPPResource *)aResource
{
	if((self = [super init]))
	{
		user = [aUser retain];
		resource = [aResource retain];
	}
	return self;
}

- (void)dealloc
{
	[user release];
	[resource release];
	[super dealloc];
}

- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
	if([encoder isBycopy])
		return self;
	else
		return [NSDistantObject proxyWithLocal:self connection:[encoder connection]];
}

- (id)initWithCoder:(NSCoder *)coder
{
	if((self = [super init]))
	{
		if([coder allowsKeyedCoding])
		{
			user     = [[coder decodeObjectForKey:@"user"] retain];
			resource = [[coder decodeObjectForKey:@"resource"] retain];
		}
		else
		{
			user     = [[coder decodeObject] retain];
			resource = [[coder decodeObject] retain];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if([coder allowsKeyedCoding])
	{
		[coder encodeObject:user     forKey:@"user"];
		[coder encodeObject:resource forKey:@"resource"];
	}
	else
	{
		[coder encodeObject:user];
		[coder encodeObject:resource];
	}
}

- (XMPPUser *)user
{
	return user;
}

- (XMPPResource *)resource
{
	return resource;
}

- (NSString *)displayName
{
	return [self mojoDisplayName];
}

- (NSString *)mojoDisplayName
{
	return [user mojoDisplayName:resource];
}

- (NSString *)libraryID
{
	return [resource libraryID];
}

- (NSString *)shareName
{
	return [resource shareName];
}

- (BOOL)zlibSupport
{
	return [resource zlibSupport];
}

- (BOOL)gzipSupport
{
	return [resource gzipSupport];
}

- (BOOL)requiresPassword
{
	return [resource requiresPassword];
}

- (BOOL)requiresTLS
{
	return [resource requiresTLS];
}

- (int)numSongs
{
	return [resource numSongs];
}

- (NSComparisonResult)compare:(XMPPUserAndMojoResource *)another
{
	return [[self mojoDisplayName] compare:[another mojoDisplayName]];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"XMPPUserAndMojoResource: %@", [[resource jid] full]];
}

- (BOOL)isEqual:(id)anObject
{
	if([anObject isMemberOfClass:[self class]])
	{
		XMPPUserAndMojoResource *another = (XMPPUserAndMojoResource *)anObject;
		
		return [resource isEqual:[another resource]];
	}
	
	return NO;
}

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
- (unsigned)hash
{
	return [resource hash];
}
#else
- (NSUInteger)hash
{
	return [resource hash];
}
#endif

@end
