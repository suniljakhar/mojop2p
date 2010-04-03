#import <Foundation/Foundation.h>

@class SearchQuery;
@class SearchTerm;


@interface ITunesSearch : NSObject
{
	NSMutableArray *matchingTracks;
}

- (id)initWithSearchQuery:(NSDictionary *)query;

- (NSArray *)matchingTracks;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface SearchQuery : NSObject
{
	NSMutableArray *searchFields;
	NSUInteger searchFieldIndex;
	
	NSMutableDictionary *termDictionary;
	
	NSMutableArray *searchTerms;
	NSUInteger searchTermIndex;
	
	NSUInteger totalPoints;
	NSUInteger earnedPoints;
	
	BOOL hasExclusiveTerms;
	BOOL foundExclusiveTerm;
	
	BOOL missedRequiredTerm;
	
	NSUInteger maxNumberOfResults;
}

- (id)initWithQuery:(NSDictionary *)query;

- (NSString *)nextSearchField;

- (NSString *)nextSearchTerm;

- (void)setFoundSearchTerm:(BOOL)flag;

- (BOOL)isMatch;

- (NSUInteger)maxNumberOfResults;

- (void)reset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface SearchTerm : NSObject
{
	NSString *term;
	BOOL isInclusive;
	BOOL isRequired;
	BOOL isFound;
}

- (id)initWithTerm:(NSString *)term inclusive:(BOOL)flagInclusive required:(BOOL)flagRequired;

- (NSString *)term;
- (BOOL)isInclusive;
- (BOOL)isExclusive;
- (BOOL)isRequired;
- (BOOL)isFound;

- (void)setIsFound:(BOOL)flag;

@end