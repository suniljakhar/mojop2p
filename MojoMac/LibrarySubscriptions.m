#import "LibrarySubscriptions.h"
#import "MojoDefinitions.h"
#import "ITunesData.h"


/**
 * This class represents the subscriptions to a specific iTunes library.
 * The specific library is indicated by the libraryID, which is a persistent UUID.
 * 
 * This file is included in both the MojoHelper and Mojo target.
 * All LibrarySubscriptions objects are stored in the MojoHelper, and it's preferences.
 * Mojo accesses all of it's LibrarySubscriptions objects via DO.
 * MojoHelper accesses all of it's LibrarySubscriptions objects via the Subscriptions class.
**/
@implementation LibrarySubscriptions

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Initializes a new LibrarySubscriptions object that contains no subscriptions.
**/
- (id)initWithLibraryID:(NSString *)libID
{
	if((self = [super init]))
	{
		libraryID = [libID copy];
		
		subscriptions = [[NSMutableDictionary alloc] init];
		displayName   = @"";
		lastSyncDate  = [[NSDate distantPast] retain];
		isUpdating    = NO;
	}
	return self;
}

/**
 * Initializes a new LibrarySubscriptions object with the information stored in the dictionary.
**/
- (id)initWithLibraryID:(NSString *)libID dictionary:(NSDictionary *)dictionary
{
	if((self = [super init]))
	{
		libraryID = [libID copy];
		
		NSDictionary *temp1 = (NSDictionary *)[dictionary objectForKey:PREFS_SUBSCRIPTIONS];
		subscriptions = [temp1 mutableCopy];
		if(subscriptions == nil)
		{
			subscriptions = [[NSMutableDictionary alloc] init];
		}
		
		NSString *temp2 = (NSString *)[dictionary objectForKey:PREFS_DISPLAY_NAME];
		displayName = [temp2 copy];
		if(displayName == nil)
		{
			displayName = @"";
		}
		
		NSDate *temp3 = (NSDate *)[dictionary objectForKey:PREFS_LAST_SYNC];
		lastSyncDate = [temp3 copy];
		if(lastSyncDate == nil)
		{
			lastSyncDate = [[NSDate distantPast] retain];
		}
		
		isUpdating = NO;
	}
	return self;
}

/**
 * Standard Destructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
//	NSLog(@"Destroying %@", self);
	
	[libraryID release];
	[subscriptions release];
	[displayName release];
	[lastSyncDate release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Encoding, Decoding:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called during Distributed Object messaging.
 * It basically asks this class if a returned variable (to a different task) should be a copy or reference.
 * The default is to only pass back proxy objects to this object.
 * But we want to allow copies to go to the other task, so we override this method to allow it.
**/
- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder
{
	if([encoder isByref])
		return [NSDistantObject proxyWithLocal:self connection:[encoder connection]];
	else
		return self;
}

/**
 * This method is called to create a new instance from an archive or serialization.
 * The given coder may be of several different types, so this must be taken into consideration.
 * If the coder allows for keyed coding, we can access (decode) our variables like they're in a dictionary.
 * Otherwise we must access (decode) our variables in the same sequence in which they were encoded.
**/
- (id)initWithCoder:(NSCoder *)coder
{
	if((self = [super init]))
	{
		if([coder allowsKeyedCoding])
		{
			libraryID     = [[coder decodeObjectForKey:PREFS_LIBRARY_ID] copy];
			subscriptions = [[coder decodeObjectForKey:PREFS_SUBSCRIPTIONS] mutableCopy];
			displayName   = [[coder decodeObjectForKey:PREFS_DISPLAY_NAME] copy];
			lastSyncDate  = [[coder decodeObjectForKey:PREFS_LAST_SYNC] copy];
			isUpdating    = [coder decodeBoolForKey:PREFS_IS_UPDATING];
		}
		else
		{
			int version = [[coder decodeObject] intValue];
			
			if(version == 2)
			{
				libraryID     = [[coder decodeObject] copy];
				subscriptions = [[coder decodeObject] mutableCopy];
				displayName   = [[coder decodeObject] copy];
				lastSyncDate  = [[coder decodeObject] copy];
				isUpdating    = [[coder decodeObject] boolValue];
			}
		}
	}
	return self;
}

/**
 * This method is called to create an archive or serialization of this instance.
 * The given coder may be of several different types, so this must be taken into consideration.
 * If the coder allows for keyed coding, we can encode our variables in a manner similar to a dictionary.
 * Otherwise we must encode our variables in a particular sequence, since they must be decoded in this same sequence.
**/
- (void)encodeWithCoder:(NSCoder *)coder
{
	if([coder allowsKeyedCoding])
	{
		[coder encodeObject:libraryID     forKey:PREFS_LIBRARY_ID];
		[coder encodeObject:subscriptions forKey:PREFS_SUBSCRIPTIONS];
		[coder encodeObject:displayName   forKey:PREFS_DISPLAY_NAME];
		[coder encodeObject:lastSyncDate  forKey:PREFS_LAST_SYNC];
		[coder encodeBool:isUpdating      forKey:PREFS_IS_UPDATING];
	}
	else
	{
		[coder encodeObject:[NSNumber numberWithInt:2]];
		[coder encodeObject:libraryID];
		[coder encodeObject:subscriptions];
		[coder encodeObject:displayName];
		[coder encodeObject:lastSyncDate];
		[coder encodeObject:[NSNumber numberWithBool:isUpdating]];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Copying:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns a deep copy of this object
 *
 * This method is required for implementations of the NSCopying protocol.
 * It is typically invoked by calling 'copy' on the object.
 * The copy is a deep copy, and all variables may be changed without affecting the original.
 * The copy is implicitly retained by the sender, who is responsible for releasing it.
 * 
 * @param  zone - The zone in which the copy is done.
**/
- (id)copyWithZone:(NSZone *)zone
{
	LibrarySubscriptions *selfCopy = [[LibrarySubscriptions alloc] initWithLibraryID:libraryID];
	
	[selfCopy->subscriptions release];
	selfCopy->subscriptions = [subscriptions mutableCopy];
	
	[selfCopy->displayName release];
	selfCopy->displayName = [displayName copy];
	
	[selfCopy->lastSyncDate release];
	selfCopy->lastSyncDate = [lastSyncDate copy];
	
	selfCopy->isUpdating = isUpdating;
	
	return selfCopy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Comparing:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method compares 2 separate LibrarySubscriptions objects, and returns whether or not they are essentially equal.
 * Essential Equality is based on the non-volatile variables of the object, meaning the following must be the same:
 *   libraryID - If these are different, the subscriptions are for differnt libraries, and obviously are not equal.
 *   subscriptions - These must be to the same playlists (playlist persistent ID), with the same "My Playlist" name.
 * 
 * Other variables are ignored because they may be constantly changed without the user actually changing any of
 * his/her playlist subscriptions.  EG - lastSyncDate will be constantly updated, regardless of playlist changes.
 * 
 * This method was originally written to see if the user actually made any changes after clicking the 'OK' button
 * in the edit playlist subscriptions sheet.  This method will return exactly what we're looking for.
**/
- (BOOL)isEssentiallyEqual:(LibrarySubscriptions *)ls
{
	// Are both subscription sets for the same music library?
	if([libraryID isEqualToString:[ls libraryID]])
	{
		// Do both subscription sets have the same number of subscribed playlists?
		if([self numberOfSubscribedPlaylists] == [ls numberOfSubscribedPlaylists])
		{
			// Are both subscription sets subscribed to the exact same playlists?
			// And do they both have the exact same names for each playlist?
			
			NSArray *keys = [subscriptions allKeys];
			
			BOOL hasSamePlaylistSubscriptions = YES;
			
			int i;
			for(i = 0; i < [keys count] && hasSamePlaylistSubscriptions; i++)
			{
				NSDictionary *selfDict = [subscriptions objectForKey:[keys objectAtIndex:i]];
				NSDictionary *lsDict = [ls->subscriptions objectForKey:[keys objectAtIndex:i]];
				
				if(lsDict != nil)
				{
					NSString *selfDict_myName = [selfDict objectForKey:SUBSCRIPTION_MYNAME];
					NSString *lsDict_myName = [lsDict objectForKey:SUBSCRIPTION_MYNAME];
					
					if(![selfDict_myName isEqualToString:lsDict_myName])
					{
						hasSamePlaylistSubscriptions = NO;
					}
				}
				else
				{
					hasSamePlaylistSubscriptions = NO;
				}
			}
			
			return hasSamePlaylistSubscriptions;
		}
	}
	
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Saving To Defaults:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method returns an NSDictionary that can be saved to the user defaults dictionary.
 * The resulting dictionary can later be used to restore the object using the initWithDictionary method.
**/
- (NSDictionary *)prefsDictionary
{
	NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithCapacity:3];
	
	// Note: There is no need to save the libraryID or the isUpdating flag to the user defaults system
	
	[prefs setObject:displayName   forKey:PREFS_DISPLAY_NAME];
	[prefs setObject:lastSyncDate  forKey:PREFS_LAST_SYNC];
	[prefs setObject:subscriptions forKey:PREFS_SUBSCRIPTIONS];
	
	return prefs;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General API:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the number of playlists the user is subscribed to for this library.
**/
- (int)numberOfSubscribedPlaylists
{
	return [subscriptions count];
}


/**
 * Returns an array of playlists the user is subscribed to with the given data.
 * The array is thus an array of NSDictionaries, each obtained by invoking playlistWithIndex: on data.
 * This method also verifies that each subscribed playlist is still in data.
 * If it's not, the playlist subscription is removed.
**/
- (NSArray *)subscribedPlaylistsWithData:(ITunesData *)data
{
	// Get all the persistent playlist IDs of the subscribed playlists
	NSArray *allKeys = [subscriptions allKeys];
	
	// Create a mutable array to store the actual playlist dictionaries
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[allKeys count]];
	
	int i;
	for(i = 0; i < [allKeys count]; i++)
	{
		// Get the current key, which is really just the playlist persistent ID
		NSString *playlistPersistentID = [allKeys objectAtIndex:i];
		
		// Get the playlistSubscription dictionary for the current key
		// Remember this is a dictionary with 2 keys: SUBSCRIPTION_INDEX and SUBSCRIPTION_MYNAME
		NSDictionary *playlistSubscription = [subscriptions objectForKey:playlistPersistentID];
		
		// Extract the playlistIndex from the playlistSubscription dictionary
		int oldPlaylistIndex = [[playlistSubscription objectForKey:SUBSCRIPTION_INDEX] intValue];
		
		// Now validate the playlistIndex
		// We need to do this because the playlistIndex doesn't remain constant in the iTunes XML file
		// Only the persistentPlaylistID remains constant
		int newPlaylistIndex = [data validatePlaylistIndex:oldPlaylistIndex
								  withPersistentPlaylistID:playlistPersistentID];
		
		// Check for a valid playlistIndex
		// If the validatePlaylistIndex:withPersistentPlaylistID: method doesn't find the playlist, it returns -1
		// Otherwise the playlist index is guaranteed to be correct
		if(newPlaylistIndex >= 0)
		{
			// The playlist is still in the iTunes library, but has the playlist index changed?
			if(oldPlaylistIndex != newPlaylistIndex)
			{
				// Update the playlist index so it's correct next time
				NSMutableDictionary *newPlaylistSubscription = [[playlistSubscription mutableCopy] autorelease];
				[newPlaylistSubscription setObject:[NSNumber numberWithInt:newPlaylistIndex] forKey:SUBSCRIPTION_INDEX];
				
				[subscriptions setObject:newPlaylistSubscription forKey:playlistPersistentID];
			}
			
			// We can go ahead and add it to our array
			[result addObject:[data playlistForIndex:newPlaylistIndex]];
		}
		else
		{
			// The playlist no longer exists in the iTunes library
			// We may as well remove it from our list of subscriptions
			[subscriptions removeObjectForKey:playlistPersistentID];
		}
	}
	
	return result;
}


/**
 * Returns whether or not the user is subscribed to the given playlist (for this library).
**/
- (BOOL)isSubscribedToPlaylist:(NSDictionary *)playlist
{
	if([subscriptions objectForKey:[playlist objectForKey:PLAYLIST_PERSISTENTID]])
		return YES;
	else
		return NO;
}


/**
 * If the user is subscribed to the given playlist (for this library) they are unsubscribed from it.
**/
- (void)unsubscribeFromPlaylist:(NSDictionary *)playlist
{
	[subscriptions removeObjectForKey:[playlist objectForKey:PLAYLIST_PERSISTENTID]];
}


/**
 * Removes all playlist subscriptions.
**/
- (void)unsubscribeFromAllPlaylists
{
	[subscriptions removeAllObjects];
}


/**
 * Subscribes the user to the given playlist (for this library).
 * If the user was already subscribed to the given playlist, the subscription is updated with the given information.
**/
- (void)subscribeToPlaylist:(NSDictionary *)playlist withPlaylistIndex:(int)index myName:(NSString *)myName
{
	NSMutableDictionary *playlistInfo = [NSMutableDictionary dictionary];
	
	[playlistInfo setObject:[NSNumber numberWithInt:index] forKey:SUBSCRIPTION_INDEX];
	[playlistInfo setObject:myName forKey:SUBSCRIPTION_MYNAME];
	
	// Convert NSMutableDictionary into NSDictionary
	// This prevents the key's value from being changed in any way outside the designed class methods
	NSDictionary *plistInfo = [[playlistInfo copy] autorelease];
	
	// Add subscription to list of subscriptions
	[subscriptions setObject:plistInfo forKey:[playlist objectForKey:PLAYLIST_PERSISTENTID]];
	
	// We also need to update the last time this library was updated
	[lastSyncDate release];
	lastSyncDate = [[NSDate distantPast] retain];
}


/**
 * If the user is subscribed to the given playlist (for this library)
 * this method returns the local playlist name to be used for syncronization.
 * If the user is not subscribed to the given playlist, this method simply returns the name of the playlist.
**/
- (NSString *)myNameForPlaylist:(NSDictionary *)playlist
{
	NSString *playlistPersistentID = [playlist objectForKey:PLAYLIST_PERSISTENTID];
	
	NSDictionary *playlistSubscription = [subscriptions objectForKey:playlistPersistentID];
	
	if(playlistSubscription)
		return [playlistSubscription objectForKey:SUBSCRIPTION_MYNAME];
	else
		return [playlist objectForKey:PLAYLIST_NAME];
}

/**
 * Returns read-only library ID attribute.
**/
- (NSString *)libraryID
{
	return libraryID;
}

/**
 * Returns the last known display name for the subscriptions.
**/
- (NSString *)displayName {
	return displayName;
}
- (void)setDisplayName:(NSString *)name
{
	if(![displayName isEqualToString:name])
	{
		[displayName release];
		displayName = [name copy];
	}
}

/**
 * Returns the last time the subscriptions to this library were fully updated.
**/
- (NSDate *)lastSyncDate {
	return lastSyncDate;
}
- (void)setLastSyncDate:(NSDate *)date
{
	if(![lastSyncDate isEqualToDate:date])
	{
		[lastSyncDate release];
		lastSyncDate = [date copy];
	}
}

/**
 * Returns whether or not this subscription is currently being updated.
 * This should be set to YES when the library is being updated.
 * This prevents it from being updated twice at one time.
**/
- (BOOL)isUpdating {
	return isUpdating;
}
- (void)setIsUpdating:(BOOL)flag
{
	isUpdating = flag;
}

@end
