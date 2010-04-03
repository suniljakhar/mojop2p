#import "BonjourResource.h"
#import "BonjourUtilities.h"
#import "MojoDefinitions.h"

#ifdef TARGET_MOJO_HELPER
#import "HelperAppDelegate.h"
#endif


@implementation BonjourResource

- (id)initWithNetService:(NSNetService *)aNetService
{
	if((self = [super init]))
	{
		netService = [aNetService retain];
		[netService setDelegate:self];
		[netService startMonitoring];
		
		resolvers = [[NSMutableArray alloc] initWithCapacity:1];
	}
	return self;
}

- (void)dealloc
{
	[netService setDelegate:nil];
	[netService stopMonitoring];
	[netService release];
	[txtRecordData release];
	[resolvers release];
	[nickname release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encoding, Decoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
		NSString *domain, *type, *name;
		
		if([coder allowsKeyedCoding])
		{
			domain        = [coder decodeObjectForKey:@"domain"];
			type          = [coder decodeObjectForKey:@"type"];
			name          = [coder decodeObjectForKey:@"name"];
			txtRecordData = [[coder decodeObjectForKey:@"txtRecordData"] retain];
			nickname      = [[coder decodeObjectForKey:@"nickname"] retain];
		}
		else
		{
			domain        = [coder decodeObject];
			type          = [coder decodeObject];
			name          = [coder decodeObject];
			txtRecordData = [[coder decodeObject] retain];
			nickname      = [[coder decodeObject] retain];
		}
		
		netService = [[NSNetService alloc] initWithDomain:domain type:type name:name];
		[netService setDelegate:self];
		
		resolvers = [[NSMutableArray alloc] initWithCapacity:1];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if([coder allowsKeyedCoding])
	{
		[coder encodeObject:[self domain]   forKey:@"domain"];
		[coder encodeObject:[self type]     forKey:@"type"];
		[coder encodeObject:[self name]     forKey:@"name"];
		[coder encodeObject:txtRecordData   forKey:@"txtRecordData"];
		[coder encodeObject:[self nickname] forKey:@"nickname"];
	}
	else
	{
		[coder encodeObject:[self domain]];
		[coder encodeObject:[self type]];
		[coder encodeObject:[self name]];
		[coder encodeObject:txtRecordData];
		[coder encodeObject:[self nickname]];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Standard Information
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the NSNetService domain.
**/
- (NSString *)domain
{
	return [netService domain];
}

/**
 * Returns the NSNetService type.
**/
- (NSString *)type
{
	return [netService type];
}

/**
 * Returns the NSNetService name.
**/
- (NSString *)name
{
	return [netService name];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark TXT Record Information
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Extracts the iTunes library persistent ID from a given NSNetService.
 * If not library ID exists for the given service, the empty string will be returned.
**/
- (NSString *)libraryID
{
	return [BonjourUtilities libraryIDForTXTRecordData:txtRecordData];
}

/**
 * Extracts the share name from this service.
 * If no share name exists in the txtRecord (or it's an empty string), the NSNetService name is returned.
**/
- (NSString *)shareName
{
	return [BonjourUtilities shareNameForTXTRecordData:txtRecordData];
}

/**
 * Inspects the txtRecordData of a this service to see if it supports zlib compression
**/
- (BOOL)zlibSupport
{
	return [BonjourUtilities zlibSupportForTXTRecordData:txtRecordData];
}

/**
 * Inspects the txtRecordData of a this service to see if it supports zlib compression
**/
- (BOOL)gzipSupport
{
	return [BonjourUtilities gzipSupportForTXTRecordData:txtRecordData];
}

/**
 * Inspects the txtRecordData of a this service to see if it requires a password to connect
**/
- (BOOL)requiresPassword
{
	return [BonjourUtilities requiresPasswordForTXTRecordData:txtRecordData];
}

/**
 * Inspects the txtRecordData of a this service to see if it requires a secure connection
**/
- (BOOL)requiresTLS
{
	return [BonjourUtilities requiresTLSForTXTRecordData:txtRecordData];
}

/**
 * Extracts the number of songs available from a given NSNetService.
**/
- (int)numSongs
{
	return [BonjourUtilities numSongsForTXTRecordData:txtRecordData];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Composite Information
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)nickname
{
#ifdef TARGET_MOJO_HELPER
	NSDictionary *nicknames = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PREFS_DISPLAY_NAMES];
	return [nicknames objectForKey:[self libraryID]];
#else
	return nickname;
#endif
}

- (NSString *)displayName
{
	NSString *displayName = [self nickname];
	
	if(displayName && ![displayName isEqualToString:@""])
	{
		return displayName;
	}
	else
	{
		NSString *shareName = [self shareName];
		
		if(shareName && ![shareName isEqualToString:@""])
			return shareName;
		else
			return [self name];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Resolving
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Begins resolving the underlying NSNetService object with a timeout of 5 seconds.
 * The sender will receive either a bonjourResource:didResolveAddresses: or bonjourResource:didNotResolve: method call.
**/
- (void)resolveForSender:(id)sender
{
	// Make sure not to add a resolving object twice to the list of resolver requests
	// This would cause the sender object to receive the delegate callbacks twice
	if(![resolvers containsObject:sender])
	{
		// Add sender object to list or resolver requests
		[resolvers addObject:sender];
		
		// If this is the first object to ask for the service to be resolved, start resolving the service
		if([resolvers count] == 1)
		{
			[netService resolveWithTimeout:5.0];
		}
	}
}

/**
 * Removes the given sender from the resolving process.
 * The sender will no longer receive a delegate method call.
**/
- (void)stopResolvingForSender:(id)sender
{
	[resolvers removeObject:sender];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSNetService Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifdef TARGET_MOJO_HELPER
/**
 * Called immediately after a net service is discovered, and whenever it's txt record is updated.
**/
- (void)netService:(NSNetService *)ns didUpdateTXTRecordData:(NSData *)data
{
	// Note: Only the MojoHelper monitors the netService for txt record updates
	
	// Save the updated data to our stored dictionary
	// We do this because the OS doesn't seem to reliably update the NSNetService object after it's been resolved
	[txtRecordData autorelease];
	txtRecordData = [data retain];
	
	// Post notification of updated service
	[[NSNotificationCenter defaultCenter] postNotificationName:DidUpdateLocalServiceNotification object:self];
	[[[NSApp delegate] mojoProxy] postNotificationWithName:DidUpdateLocalServiceNotification];
}
#endif

/**
 * Called after the NSNetService has resolved an address, or multiple addresses
**/
- (void)netServiceDidResolveAddress:(NSNetService *)ns
{
	NSArray *addresses = [ns addresses];
	
	while([resolvers count] > 0)
	{
		id sender = [resolvers lastObject];
		
		if([sender respondsToSelector:@selector(bonjourResource:didResolveAddresses:)])
		{
			[sender bonjourResource:self didResolveAddresses:addresses];
		}
		[resolvers removeLastObject];
	}
	
	// Don't forget to cancel our resolve request (mandatory in Leopard)
	[ns stop];
}

/**
 * Called if the net service fails to resolve any address.
**/
- (void)netService:(NSNetService *)ns didNotResolve:(NSDictionary *)errorDict
{
	while([resolvers count] > 0)
	{
		id sender = [resolvers lastObject];
		
		if([sender respondsToSelector:@selector(bonjourResource:didNotResolve:)])
		{
			[sender bonjourResource:self didNotResolve:errorDict];
		}
		[resolvers removeLastObject];
	}
	
	// Don't forget to cancel our resolve request (mandatory in Leopard)
	[ns stop];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Comparison Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the result of invoking compareByName:options: with no options.
**/
- (NSComparisonResult)compareByName:(BonjourResource *)user
{
	return [self compareByName:user options:0];
}

/**
 * This method compares the two users according to their name.
 * If either of the users has no set share name (or has an empty string share name),
 * the name is considered to be service name.
 * 
 * Options for the search: you can combine any of the following using a C bitwise OR operator:
 * NSCaseInsensitiveSearch, NSLiteralSearch, NSNumericSearch.
 * See "String Programming Guide for Cocoa" for details on these options.
**/
- (NSComparisonResult)compareByName:(BonjourResource *)user options:(unsigned)mask
{
	NSString *selfName = [self displayName];
	NSString *userName = [user displayName];
	
	return [selfName compare:userName options:mask];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSObject Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [NSString stringWithFormat:@"BonjourResource: %@ (%@)", [self displayName], [self netServiceDescription]];
}

- (NSString *)netServiceDescription
{
	return [NSString stringWithFormat:@"%@.%@%@", [self name], [self type], [self domain]];
}

- (BOOL)isEqual:(id)anObject
{
	if([anObject isMemberOfClass:[self class]])
	{
		BonjourResource *another = (BonjourResource *)anObject;
		
		return [[self netServiceDescription] isEqualToString:[another netServiceDescription]];
	}
	
	return NO;
}

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
- (unsigned)hash
{
	return [[self netServiceDescription] hash];
}
#else
- (NSUInteger)hash
{
	return [[self netServiceDescription] hash];
}
#endif

@end
