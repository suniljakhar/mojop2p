#import <Cocoa/Cocoa.h>
#import "ServerListManager.h"
#import "AppDelegate.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#ifdef CONFIGURATION_DEBUG
  #define SERVER_LIST_URL       @"http://www.deusty.com/jabber/servers.xml"
  #define SERVER_LIST_DOWNLOAD  @"newServers.xml"
  #define SERVER_LIST_FILENAME  @"servers.xml"
#else
  #define SERVER_LIST_URL       @"http://www.deusty.com/jabber/servers.xml"
  #define SERVER_LIST_DOWNLOAD  @"newServers.xml"
  #define SERVER_LIST_FILENAME  @"servers.xml"
#endif

#define UPDATE_INTERVAL  (60 * 60 * 48)


@implementation ServerListManager

+ (NSString *)serverListPath
{
	return [[[NSApp delegate] applicationSupportDirectory] stringByAppendingPathComponent:SERVER_LIST_FILENAME];
}

+ (NSString *)newServerListPath
{
	return [[[NSApp delegate] applicationSupportDirectory] stringByAppendingPathComponent:SERVER_LIST_DOWNLOAD];
}

+ (BOOL)serverListNeedsUpdate
{
	NSString *path = [self serverListPath];
	
	NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES];
	NSDate *lastMod = [attributes objectForKey:NSFileCreationDate];
	
	NSTimeInterval ti = [[NSDate date] timeIntervalSinceDate:lastMod];
	NSTimeInterval ui = UPDATE_INTERVAL;
	
	if(DEBUG_VERBOSE)
	{
		if(isnan(ti))
		{
			DDLogVerbose(@"ServerListManager: TimeSinceLastUpdate: Never");
		}
		else
		{
			int days    = (int)ti / (60 * 60 * 24);
			int hours   = (int)ti % (60 * 60 * 24) / (60 * 60);
			int minutes = (int)ti % (60 * 60 * 24) % (60 * 60) / 60;
			int seconds = (int)ti % (60 * 60 * 24) % (60 * 60) % 60;
			
			DDLogVerbose(@"ServerListManager: TimeSinceLastUpdate: %i:%i:%i:%i", days, hours, minutes, seconds);
		}
	}
	
	return ((isnan(ti)) || (ti > ui) || (ti < 0));
}

+ (void)updateServerList
{
	NSURL *url = [NSURL URLWithString:SERVER_LIST_URL];
	NSURLRequest *request = [NSURLRequest requestWithURL:url];
	
	NSURLDownload *downloader = [[NSURLDownload alloc] initWithRequest:request delegate:self];
	[downloader setDestination:[self newServerListPath] allowOverwrite:YES];
}

+ (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	NSString *downloadPath = [self newServerListPath];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:downloadPath])
	{
		[[NSFileManager defaultManager] removeFileAtPath:downloadPath handler:nil];
	}
	
	[download autorelease];
	DDLogError(@"ServerListManager: Failed to update server list: %@", error);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:DidNotUpdateServerListNotification object:self];
}

+ (void)downloadDidFinish:(NSURLDownload *)download
{
	NSString *filePath = [self serverListPath];
	NSString *downloadPath = [self newServerListPath];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
		if(![[NSFileManager defaultManager] removeFileAtPath:filePath handler:nil])
		{
			DDLogError(@"ServerListManager: Unable to delete old server file!");
		}
	}
	
	NSDate *now = [NSDate date];
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:2];
	[attributes setObject:now forKey:NSFileCreationDate];
	[attributes setObject:now forKey:NSFileModificationDate];
	
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	if(![[NSFileManager defaultManager] changeFileAttributes:attributes atPath:downloadPath])
	{
		DDLogError(@"ServerListManager: Unable to update attributes of new servers file!");
	}
#else
	if(![[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:downloadPath error:nil])
	{
		DDLogError(@"ServerListManager: Unable to update attributes of new servers file!");
	}
#endif
	if(![[NSFileManager defaultManager] movePath:downloadPath toPath:filePath handler:nil])
	{
		DDLogError(@"ServerListManager: Unable to rename new servers file!");
	}
	
	[download autorelease];
	DDLogInfo(@"ServerListManager: Finished updating server list");
	
	[[NSNotificationCenter defaultCenter] postNotificationName:DidUpdateServerListNotification object:self];
}

@end
