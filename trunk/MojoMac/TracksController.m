#import "TracksController.h"
#import "ITunesTrack.h"


@implementation TracksController

/**
 * Returns the current searchString being used to filter the table.
**/
- (NSString *)searchString
{
	return searchString;
}

/**
 * Sets the new search string to be used for filtering the table.
 * Note that this method doesn't update the table.  Calling methods will have to do that themselves.
**/
- (void)setSearchString:(NSString *)newSearchString
{
	if(![searchString isEqualToString:newSearchString])
	{
		// Update the search string
        [searchString autorelease];
        searchString = [newSearchString copy];
		
		// And update the arrangedObjects
		[self rearrangeObjects];
    }
}

/**
 * This method overrides the arrangeObjects: method of NSArrayController.
 * It adds proper searching based on the searchString, and according to iTunes searching rules.
**/
- (NSArray *)arrangeObjects:(NSArray *)objects
{
	// If there is no searchString, we can just return the usual
    if((searchString == nil) || ([searchString isEqualToString:@""]))
	{
		return [super arrangeObjects:objects];   
	}
	
	// Seperate searchStr by its components - IE: ["John", "Mayer", "Wonderland"]
	NSArray *temp = [searchString componentsSeparatedByString:@" "];
	
	// For some bizarre reason, temp contains empty strings...get rid of that shit!
	NSMutableArray *components = [NSMutableArray arrayWithArray:temp];
	[components removeObject:@""];
	
	// Create array to hold tracks that match our search
	NSMutableArray *matchedObjects = [NSMutableArray arrayWithArray:objects];
	
	// Perform search for each component, narrowing results each time
	int i, j;
	for(i = 0; i < [components count]; i++)
	{
		NSString *str = [components objectAtIndex:i];
		
		NSMutableArray *results = [NSMutableArray array];
		
		for(j = 0; j < [matchedObjects count]; j++)
		{
			ITunesTrack *track = [matchedObjects objectAtIndex:j];
			
			NSString *name   = [track name];
			NSString *artist = [track artist];
			NSString *album  = [track album];
			
			if((name != nil) && ([name rangeOfString:str options:NSCaseInsensitiveSearch].location != NSNotFound))
			{
				[results addObject:track];
			}
			else if((artist != nil) && ([artist rangeOfString:str options:NSCaseInsensitiveSearch].location != NSNotFound))
			{
				[results addObject:track];
			}
			else if((album != nil) && ([album rangeOfString:str options:NSCaseInsensitiveSearch].location != NSNotFound))
			{
				[results addObject:track];
			}
		}
		
		// Save current table and continue searching and narrowing results
		matchedObjects = results;
	}
	
    return [super arrangeObjects:matchedObjects];
}

/**
 * This method overrides NSArrayController's setSortDescriptors: method.
 * In iTunes, when you sort by the artist column, it actually sorts by artist, then album, then track.
 * In fact, iTunes often uses multiple sort descriptors to get smarter sorting.
 * We inspect the sort descriptors here, and change them to mimic iTune's behavior.
**/
- (void)setSortDescriptors:(NSArray *)sortDescriptors
{
	// Get the primary sort key we're currently using
	NSSortDescriptor *primarySortDescriptor = [sortDescriptors objectAtIndex:0];
	
	// We almost always need to sort by one of these 3
	NSSortDescriptor *artist, *album, *track;
	
	artist = [[[NSSortDescriptor alloc] initWithKey:@"artist"
										  ascending:[primarySortDescriptor ascending]
										   selector:@selector(caseInsensitiveCompare:)] autorelease];
	
	album  = [[[NSSortDescriptor alloc] initWithKey:@"album"
										  ascending:[primarySortDescriptor ascending]
										   selector:@selector(caseInsensitiveCompare:)] autorelease];
	
	track  = [[[NSSortDescriptor alloc] initWithKey:@"trackNumber"
										  ascending:[primarySortDescriptor ascending]] autorelease];
	
	
	if([[primarySortDescriptor key] isEqualToString:@"artist"])
	{
		[super setSortDescriptors:[NSArray arrayWithObjects:artist, album, track, nil]];
	}
	else if([[primarySortDescriptor key] isEqualToString:@"album"])
	{
		[super setSortDescriptors:[NSArray arrayWithObjects:album, track, nil]];
	}
	else if([[primarySortDescriptor key] isEqualToString:@"trackNumber"])
	{
		[super setSortDescriptors:[NSArray arrayWithObjects:track, album, nil]];
	}
	else
	{
		[super setSortDescriptors:[NSArray arrayWithObjects:primarySortDescriptor, artist, album, track, nil]];
	}
}

@end
