#import <Cocoa/Cocoa.h>
#import "ProxyListManager.h"
#import "AppDelegate.h"
#import "MojoDefinitions.h"
#import "TigerSupport.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#ifdef CONFIGURATION_DEBUG
  #define PROXY_LIST_URL  @"http://www.deusty.com/jabber/proxies.dev.txt"
  #define PROXY_LIST_DOWNLOAD @"newProxies.dev.txt"
  #define PROXY_LIST_FILENAME @"proxies.dev.txt"
#else
  #define PROXY_LIST_URL  @"http://www.deusty.com/jabber/proxies.txt"
  #define PROXY_LIST_DOWNLOAD @"newProxies.txt"
  #define PROXY_LIST_FILENAME @"proxies.txt"
#endif

#define UPDATE_INTERVAL  (60 * 60 * 24 * 7)

// Declare private methods
@interface ProxyListManager (PrivateAPI)
+ (NSString *)proxyListPath;
+ (void)scheduleProxyListUpdate;
+ (void)updateProxyList:(NSTimer *)aTimer;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ProxyListManager

+ (void)initialize
{
	static BOOL initialized = NO;
	if(!initialized)
	{
		initialized = YES;
		
		NSString *path = [self proxyListPath];
		
		NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES];
		NSDate *lastMod = [attributes objectForKey:NSFileCreationDate];
		
		NSTimeInterval ti = [[NSDate date] timeIntervalSinceDate:lastMod];
		NSTimeInterval ui = UPDATE_INTERVAL;
		
		if(DEBUG_VERBOSE)
		{
			if(isnan(ti))
			{
				DDLogVerbose(@"ProxyListManager: TimeSinceLastUpdate: Never");
			}
			else
			{
				int days    = (int)ti / (60 * 60 * 24);
				int hours   = (int)ti % (60 * 60 * 24) / (60 * 60);
				int minutes = (int)ti % (60 * 60 * 24) % (60 * 60) / 60;
				int seconds = (int)ti % (60 * 60 * 24) % (60 * 60) % 60;
				
				DDLogVerbose(@"ProxyListManager: TimeSinceLastUpdate: %i:%i:%i:%i", days, hours, minutes, seconds);
			}
		}
		
		if(isnan(ti) || ti > ui || ti < 0)
		{
			NSTimeInterval shortDelay = 4.0;
			
			[NSTimer scheduledTimerWithTimeInterval:shortDelay
											 target:self
										   selector:@selector(updateProxyList:)
										   userInfo:nil
											repeats:NO];
		}
		else
		{
			NSTimeInterval later = ui - ti;
			
			[NSTimer scheduledTimerWithTimeInterval:later
											 target:self
										   selector:@selector(updateProxyList:)
										   userInfo:nil
											repeats:NO];
		}
	}
}

+ (NSString *)proxyListPath
{
	return [[[NSApp delegate] applicationSupportDirectory] stringByAppendingPathComponent:PROXY_LIST_FILENAME];
}

+ (NSString *)proxyListDownloadPath
{
	return [[[NSApp delegate] applicationSupportDirectory] stringByAppendingPathComponent:PROXY_LIST_DOWNLOAD];
}

+ (void)updateProxyList:(NSTimer *)aTimer
{
	NSURL *url = [NSURL URLWithString:PROXY_LIST_URL];
	NSURLRequest *request = [NSURLRequest requestWithURL:url];
	
	NSURLDownload *downloader = [[NSURLDownload alloc] initWithRequest:request delegate:self];
	[downloader setDestination:[self proxyListDownloadPath] allowOverwrite:YES];
}

+ (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
	NSString *downloadPath = [self proxyListDownloadPath];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:downloadPath])
	{
		[[NSFileManager defaultManager] removeFileAtPath:downloadPath handler:nil];
	}
	
	[download autorelease];
	DDLogError(@"ProxyListManager: Failed to update proxy list: %@", error);
	
	[NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL
									 target:self
								   selector:@selector(updateProxyList:)
								   userInfo:nil
									repeats:NO];
}

+ (void)downloadDidFinish:(NSURLDownload *)download
{
	NSString *proxyPath = [self proxyListPath];
	NSString *downloadPath = [self proxyListDownloadPath];
	
	if([[NSFileManager defaultManager] fileExistsAtPath:proxyPath])
	{
		if(![[NSFileManager defaultManager] removeFileAtPath:proxyPath handler:nil])
		{
			DDLogError(@"ProxyListManager: Unable to delete old proxy file!");
		}
	}
	
	NSDate *now = [NSDate date];
	
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:2];
	[attributes setObject:now forKey:NSFileCreationDate];
	[attributes setObject:now forKey:NSFileModificationDate];
	
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	if(![[NSFileManager defaultManager] changeFileAttributes:attributes atPath:downloadPath])
	{
		DDLogError(@"ProxyListManager: Unable to update attributes of new proxy file!");
	}
#else
	if(![[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:downloadPath error:nil])
	{
		DDLogError(@"ProxyListManager: Unable to update attributes of new proxy file!");
	}
#endif
	
	if(![[NSFileManager defaultManager] movePath:downloadPath toPath:proxyPath handler:nil])
	{
		DDLogError(@"ProxyListManager: Unable to rename new proxy file!");
	}
	
	[download autorelease];
	DDLogInfo(@"ProxyListManager: Finished updating proxy list");
	
	[NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL
									 target:self
								   selector:@selector(updateProxyList:)
								   userInfo:nil
									repeats:NO];
}

+ (NSArray *)proxyList
{
	NSString *proxyPath = [self proxyListPath];
	NSMutableData *proxyData = [NSData dataWithContentsOfFile:proxyPath options:NSUncachedRead error:nil];
	
	if(proxyData == nil)
	{
		return [NSArray array];
	}
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:50];
	NSUInteger proxyDataIndex = 0;
	
	NSData *term = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
	
	while(proxyDataIndex < [proxyData length])
	{
		if(memcmp([proxyData bytes]+proxyDataIndex, [term bytes], [term length]) == 0)
		{
			NSMutableString *str = [[NSMutableString alloc] initWithBytes:[proxyData mutableBytes]
																   length:proxyDataIndex
																 encoding:NSUTF8StringEncoding];
			CFStringTrimWhitespace((CFMutableStringRef)str);
			
			if([str length] > 0)
			{
				if(![result containsObject:str])
				{
					[result addObject:str];
				}
			}
			[str release];
			
			[proxyData replaceBytesInRange:NSMakeRange(0, proxyDataIndex+1) withBytes:NULL length:0];
			proxyDataIndex = 0;
		}
		else
		{
			proxyDataIndex++;
		}
	}
	
	return result;
}

@end
