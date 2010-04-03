#import "PlaylistsController.h"

@interface PlaylistsController (PrivateAPI)
- (NSIndexPath *)indexPathFromIndexPath:(NSIndexPath *)baseIndexPath
							 inChildren:(NSArray *)children
							 childCount:(unsigned int)childCount
							   toObject:(id)object;
@end


@implementation PlaylistsController

- (void)dealloc
{
	//NSLog(@"Destroying self: %@", self);
	[super dealloc];
}

/**
 * For some reason, NSTreeController only deals with it's moronic shadow objects, and silly indexPaths.
 * Therefore, the only way to select an object, is to know it's index paths.
 * NSArrayController contains a nice setSelectedObjects method, but NSTreeController doesn't.
 * Whoever made the NSTreeController class deserves to get hit in the face with a shovel.
 * This method is a workaround for the inadequacies of NSTreeController.
**/
- (void)setSelectedObjects:(NSArray *)newSelectedObjects;
{
	NSMutableArray *indexPaths = [NSMutableArray array];
	unsigned int i;
	for(i = 0; i < [newSelectedObjects count]; i++)
	{
		id selectedObject = [newSelectedObjects objectAtIndex:i];
		
		NSIndexPath *indexPath = [self indexPathToObject:selectedObject];
		if(indexPath)
		{
			[indexPaths addObject:indexPath];
		}
	}
	
	[self setSelectionIndexPaths:indexPaths];
}

/**
 * Returns the indexPath for a real object.  Not a stupid shadow object.
 * To whoever originally made the NSTreeController class: may you get run over by a bus.
 * 
 * Note that it's not as easy as looping through an array, since everything is in a tree heirarchy.
 * We have to traverse the tree in a depth first search manner.
**/
- (NSIndexPath *)indexPathToObject:(id)object;
{
	NSArray *children = [self content];
	return [self indexPathFromIndexPath:nil inChildren:children childCount:[children count] toObject:object];
}

/**
 * Private method to traverse a tree in a depth first search manner looking for a given object.
 * If found, returns the indexPath of the object.
 * Otherwise, returns nil.
**/
- (NSIndexPath *)indexPathFromIndexPath:(NSIndexPath *)baseIndexPath
                             inChildren:(NSArray *)children
                             childCount:(unsigned int)childCount
                               toObject:(id)object;
{
	unsigned int childIndex;
	for(childIndex = 0; childIndex < childCount; childIndex++)
	{
		id childObject = [children objectAtIndex:childIndex];
		
		NSArray *childsChildren = nil;
		unsigned int childsChildrenCount = 0;
		
		NSString *leafKeyPath = [self leafKeyPath];
		
		// If this node is not a leaf, or we're not sure about it's leaf status
		if(!leafKeyPath || [[childObject valueForKey:leafKeyPath] boolValue] == NO)
		{
			// Get the key countKeyPath
			// This may or may not be defined
			NSString *countKeyPath = [self countKeyPath];
			
			// If the countKeyPath is defined, we can simply use it to fetch the count of the child's children
			if(countKeyPath)
				childsChildrenCount = [[childObject valueForKey:leafKeyPath] unsignedIntValue];
			
			// If countKeyPath is undefined, we need to fetch the children, and then count them manually
			// If countKeyPath is defined, and the number of children is greater than 0, we need to fetch the children
			if(!countKeyPath || childsChildrenCount != 0)
			{
				NSString *childrenKeyPath = [self childrenKeyPath];
				childsChildren = [childObject valueForKey:childrenKeyPath];
				if(!countKeyPath)
					childsChildrenCount = [childsChildren count];
			}
		}
		
		BOOL objectFound = [object isEqual:childObject];
		
		NSIndexPath *indexPath = (baseIndexPath == nil) ? [NSIndexPath indexPathWithIndex:childIndex] : [baseIndexPath indexPathByAddingIndex:childIndex];
		
		if(objectFound)
			return indexPath;
		
		NSIndexPath *childIndexPath = [self indexPathFromIndexPath:indexPath
														inChildren:childsChildren
														childCount:childsChildrenCount
														  toObject:object];
		if(childIndexPath)
			return childIndexPath;
	}
	
	return nil;
}

@end
