#import "ITunesSearch.h"
#import "ITunesLocalSharedData.h"
#import "DDNumber.h"

@interface SearchQuery (PrivateAPI)
- (void)updateSearchTerms;
- (void)parseQuery:(NSDictionary *)query;
- (void)createSearchFields;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ITunesSearch

- (id)initWithSearchQuery:(NSDictionary *)query
{
	if((self = [super init]))
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		ITunesLocalSharedData *data = [ITunesLocalSharedData sharedLocalITunesData];
		SearchQuery *searchQuery = [[[SearchQuery alloc] initWithQuery:query] autorelease];
		
		matchingTracks = [[NSMutableArray alloc] initWithCapacity:50];
		
		NSEnumerator *tracksEnumerator = [[data tracks] objectEnumerator];
		
		NSDictionary *track;
		while ((track = [tracksEnumerator nextObject]) && ([matchingTracks count] < [searchQuery maxNumberOfResults]))
		{
			NSString *field;
			while((field = [searchQuery nextSearchField]))
			{
				NSString *fieldValue = [track objectForKey:field];
				if(fieldValue)
				{
					NSString *term;
					while((term = [searchQuery nextSearchTerm]))
					{
						NSRange range = [fieldValue rangeOfString:term options:NSCaseInsensitiveSearch];
						
						if(range.location == NSNotFound)
							[searchQuery setFoundSearchTerm:NO];
						else
							[searchQuery setFoundSearchTerm:YES];
					}
				}
			}
			
			if([searchQuery isMatch])
			{
				[matchingTracks addObject:track];
			}
			
			[searchQuery reset];
		}
		
		[pool release];
	}
	return self;
}

- (NSArray *)matchingTracks
{
	return matchingTracks;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation SearchQuery

- (id)initWithQuery:(NSDictionary *)query
{
	if((self = [super init]))
	{
		searchFields = [[NSMutableArray alloc] initWithCapacity:3];
		searchFieldIndex = 0;
		
		termDictionary = [[NSMutableDictionary alloc] initWithCapacity:7];
		
		searchTerms = [[NSMutableArray alloc] initWithCapacity:3];
		searchTermIndex = 0;
		
		totalPoints = 0;
		earnedPoints = 0;
		
		hasExclusiveTerms = NO;
		foundExclusiveTerm = NO;
		
		missedRequiredTerm = NO;
		
		[self parseQuery:query];
		[self createSearchFields];
	}
	return self;
}

- (void)dealloc
{
	[searchFields release];
	[termDictionary release];
	[searchTerms release];
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Parsing
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)validateField:(NSString *)field
{
	if(field == nil) return nil;
	
	if([field caseInsensitiveCompare:@"Artist"] == NSOrderedSame)
	{
		return TRACK_ARTIST;
	}
	if([field caseInsensitiveCompare:@"Album"] == NSOrderedSame)
	{
		return TRACK_ALBUM;
	}
	if([field caseInsensitiveCompare:@"Name"] == NSOrderedSame)
	{
		return TRACK_NAME;
	}
	if([field caseInsensitiveCompare:@"Title"] == NSOrderedSame) // Alternative for name
	{
		return TRACK_NAME;
	}
	if([field caseInsensitiveCompare:@"Genre"] == NSOrderedSame)
	{
		return TRACK_GENRE;
	}
	if([field caseInsensitiveCompare:@"Composer"] == NSOrderedSame)
	{
		return TRACK_COMPOSER;
	}
	
	return nil;
}

- (void)parseQuery:(NSDictionary *)query
{	
	if(![NSNumber parseString:[query objectForKey:@"num"] intoNSUInteger:&maxNumberOfResults])
	{
		maxNumberOfResults = 100;
	}
	
	NSString *searchStr = [query objectForKey:@"q"];
	
	// The keys for the term dictionary will be the search fields,
	// which includes specific fields such as "artist",
	// in addition to the generic fields "any" and "all".
	// The value will be a mutable array of SearchTerm objects.
	
	[termDictionary setObject:[NSMutableArray arrayWithCapacity:5] forKey:@"all"];
	
	// Good tests:
	// 
	// query(john mayer) -> { "john", "mayer" }
	// 
	// query("john mayer" wonderland) -> { "john mayer", "wonderland" }
	// 
	// query(artist:john -mayer) -> { artist:"john", -"mayer" }
	// 
	// query(+john -mayer) -> { "john", -"mayer" }
	// 
	// query(artist:+"john mayer" artist:-trio) -> { artist:"john mayer", artist:-"trio" }
	
	NSMutableString *buffer = [NSMutableString stringWithCapacity:25];
	
	NSString *field = nil;
	
	BOOL isQuotation = NO;
	BOOL isExclusive = NO;
	
	NSUInteger i = 0;
	while(i <= [searchStr length])
	{
		unichar c = (i == [searchStr length]) ? (isQuotation ? '"' : ' ') : [searchStr characterAtIndex:i];
		
		BOOL ignore = NO;
		BOOL isWhitespace = NO;
		BOOL isColon = NO;
		
		if(c == '"')
		{
			if(isQuotation)
			{
				isQuotation = NO;
				isWhitespace = YES;
			}
			else
			{
				isQuotation = YES;
				isWhitespace = ([buffer length] > 0);
				ignore = YES;
			}
		}
		
		if(!isQuotation)
		{
			if(c == ' ' || c == '\t')
			{
				isWhitespace = YES;
			}
			else if(c == ':')
			{
				isColon = YES;
			}
			else if(c == '+')
			{
				if([buffer length] == 0)
				{
					isExclusive = NO;
					ignore = YES;
				}
			}
			else if(c == '-')
			{
				if([buffer length] == 0)
				{
					isExclusive = YES;
					ignore = YES;
				}
			}
		}
		
		if(isWhitespace)
		{
			if([buffer length] > 0)
			{
				NSString *key = (field == nil) ? @"any" : field;
				
				SearchTerm *term = [[SearchTerm alloc] initWithTerm:[[buffer copy] autorelease] 
														  inclusive:(!isExclusive)
														   required:(field != nil)];
				
				if([term isInclusive])
					totalPoints++;
				else
					hasExclusiveTerms = YES;
				
				NSMutableArray *terms = [termDictionary objectForKey:key];
				if(!terms)
				{
					terms = [NSMutableArray arrayWithCapacity:2];
					[termDictionary setObject:terms forKey:key];
				}
				
				if([term isExclusive])
				{
					[terms insertObject:term atIndex:0];
				}
				else
				{
					[terms addObject:term];
				}
				
				[[termDictionary objectForKey:@"all"] addObject:term];
				
				[term release];
				[buffer setString:@""];
			}
			
			if(field)
			{
				[field release];
				field = nil;
			}
			
			isExclusive = NO;
		}
		else if(isColon)
		{
			if(field == nil)
			{
				NSString *possibleField = [buffer copy];
				
				field = [[self validateField:possibleField] copy];
				
				[possibleField release];
			}
			
			[buffer setString:@""];
		}
		else if(!ignore)
		{
			[buffer appendFormat:@"%C", c];
		}
		
		i++;
	}
	
	if(field)
	{
		[field release];
		field = nil;
	}
	
	//	NSLog(@"termDictionary: %@", termDictionary);
}

/**
 * Creates the list of search fields from the termDictionary.
 * The list is properly sorted so as to minimize the search time required per track.
 * In other words, it puts search fields with mandatory terms at the beginning,
 * thus increasing the likelihood of ruling out a track early.
 **/
- (void)createSearchFields
{
	NSArray *allKeys = [termDictionary allKeys];
	
	BOOL hasOptionalFields = NO;
	
	NSUInteger i;
	for(i = 0; i < [allKeys count]; i++)
	{
		NSString *key = [allKeys objectAtIndex:i];
		
		if(![key isEqualToString:@"all"])
		{
			if([key isEqualToString:@"any"])
			{
				hasOptionalFields = YES;
			}
			else
			{
				[searchFields addObject:key];
			}
		}
	}
	
	if(hasOptionalFields)
	{
		// Add default fields
		
		if(![searchFields containsObject:TRACK_ARTIST])
		{
			[searchFields addObject:TRACK_ARTIST];
		}
		if(![searchFields containsObject:TRACK_NAME])
		{
			[searchFields addObject:TRACK_NAME];
		}
		if(![searchFields containsObject:TRACK_ALBUM])
		{
			[searchFields addObject:TRACK_ALBUM];
		}
	}
	
	//	NSLog(@"searchFields: %@", searchFields);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerating
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)currentSearchField
{
	NSUInteger index = searchFieldIndex - 1;
	if(index < [searchFields count])
		return [searchFields objectAtIndex:index];
	else
		return nil;
}

- (NSString *)nextSearchField
{
	if(foundExclusiveTerm || missedRequiredTerm)
	{
		// We can stop now because the search already failed
		return nil;
	}
	else if(!hasExclusiveTerms && totalPoints == earnedPoints)
	{
		// We can stop now because the search already succeeded
		return nil;
	}
	
	NSString *result = nil;
	
	if(searchFieldIndex < [searchFields count])
	{
		result = [searchFields objectAtIndex:searchFieldIndex];
		
		searchFieldIndex++;
		[self updateSearchTerms];
	}
	
	return result;
}

/**
 * Updates the list of search terms for the current search field.
 * This should be called when we change the search field.
 **/
- (void)updateSearchTerms
{
	NSUInteger i;
	
	// Example: query(artist:mayer wonderland john)
	// 
	// The first search field would be artist.
	// The artist must contain "mayer", and may contain "wonderland" and/or "john".
	// If we assume that the artist was "john mayer",
	// then the next field we search would only need to look for "wonderland". 
	
	NSString *searchField = [self currentSearchField];
	
	NSArray *requiredTerms = [termDictionary objectForKey:searchField];
	NSArray *optionalTerms = [termDictionary objectForKey:@"any"];
	
	[searchTerms removeAllObjects];
	[searchTerms addObjectsFromArray:requiredTerms];
	
	for(i = 0; i < [optionalTerms count]; i++)
	{
		SearchTerm *term = [optionalTerms objectAtIndex:i];
		if(![term isFound])
		{
			[searchTerms addObject:term];
		}
	}
	
	searchTermIndex = 0;
}

- (SearchTerm *)currentSearchTerm
{
	NSUInteger index = searchTermIndex - 1;
	if(index < [searchTerms count])
		return [searchTerms objectAtIndex:index];
	else
		return nil;
}

- (NSString *)nextSearchTerm
{
	if(foundExclusiveTerm || missedRequiredTerm)
	{
		// We can stop now because the search already failed
		return nil;
	}
	else if(!hasExclusiveTerms && totalPoints == earnedPoints)
	{
		// We can stop now because the search already succeeded
		return nil;
	}
	
	SearchTerm *searchTerm = nil;
	
	if(searchTermIndex < [searchTerms count])
	{
		searchTerm = [searchTerms objectAtIndex:searchTermIndex];
		
		searchTermIndex++;
	}
	
	return [searchTerm term];
}

- (void)setFoundSearchTerm:(BOOL)flag
{
	SearchTerm *currentTerm = [self currentSearchTerm];
	
	if(flag)
	{
		if([currentTerm isInclusive])
		{
			[currentTerm setIsFound:YES];
			earnedPoints++;
		}
		else
		{
			foundExclusiveTerm = YES;
		}
	}
	else
	{
		if([currentTerm isRequired] && [currentTerm isInclusive])
		{
			missedRequiredTerm = YES;
		}
	}
}

- (BOOL)isMatch
{
	return (!foundExclusiveTerm && !missedRequiredTerm && (totalPoints == earnedPoints));
}

- (NSUInteger)maxNumberOfResults
{
	return maxNumberOfResults;
}

- (void)reset
{
	searchFieldIndex = 0;
	earnedPoints = 0;
	foundExclusiveTerm = NO;
	missedRequiredTerm = NO;
	
	NSArray *allTerms = [termDictionary objectForKey:@"all"];
	
	NSUInteger i;
	for(i = 0; i < [allTerms count]; i++)
	{
		[[allTerms objectAtIndex:i] setIsFound:NO];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation SearchTerm

- (id)initWithTerm:(NSString *)termParam inclusive:(BOOL)flagInclusive required:(BOOL)flagRequired
{
	if((self = [super init]))
	{
		term = [termParam copy];
		
		isInclusive = flagInclusive;
		isRequired = flagRequired;
		isFound = NO;
	}
	return self;
}

- (void)dealloc
{
	[term release];
	[super dealloc];
}

- (NSString *)term {
	return term;
}
- (BOOL)isInclusive {
	return isInclusive;
}
- (BOOL)isExclusive {
	return !isInclusive;
}
- (BOOL)isRequired {
	return isRequired;
}
- (BOOL)isFound {
	return isFound;
}
- (void)setIsFound:(BOOL)flag {
	isFound = flag;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<SearchTerm:%p term(%@) inclusive(%@) required(%@) found(%@)>", self, term,
			isInclusive ? @"YES" : @"NO",
			isRequired ? @"YES" : @"NO",
			isFound ? @"YES" : @"NO"];
}

@end
