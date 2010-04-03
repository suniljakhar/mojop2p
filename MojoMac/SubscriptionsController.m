#import "SubscriptionsController.h"
#import "AppDelegate.h"
#import "MojoAppDelegate.h"
#import "MojoDefinitions.h"
#import "HelperProtocol.h"
#import "BonjourResource.h"
#import "MojoXMPP.h"
#import "LibrarySubscriptions.h"
#import "AsyncSocket.h"
#import "SocketConnector.h"
#import "HTTPClient.h"
#import "RHKeychain.h"

#import "ITunesForeignInfo.h"
#import "ITunesPlaylist.h"
#import "ITunesTrack.h"

#import "ImageAndTextCell.h"
#import "RHData.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 2
#endif
#include "DDLog.h"

#define COLUMNID_CHECKBOX    @"Checkbox"
#define COLUMNID_PLAYLIST    @"Playlist"
#define COLUMNID_MYPLAYLIST  @"MyPlaylist"

@interface SubscriptionsController (PrivateAPI)
- (void)tryCache;
- (void)resolveAddress;
- (void)setupGateway;
- (void)downloadXML;
- (void)parseITunesData:(NSString *)xmlFilePath;
- (void)updateTotalAvailable;

- (NSString *)libTempDir;
@end


@implementation SubscriptionsController

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithDockingWindow:(NSWindow *)ourDockingWindow
{
	if((self = [super initWithWindowNibName:@"SubscriptionsSheet" owner:self]))
	{
		// Store parentWindow
		dockingWindow = ourDockingWindow;
		
		// Initialize primitive variables
		gatewayPort = 0;
		totalAvailableUsingLongView = NO;
		
		// Set initial status
		status = STATUS_READY;
		
		// Interestingly enough, the NSWindowController doesn't actually load the nib file right away
		// It waits until the loadWindow method is called (usually indirectly, via showWindow:)
		// This is undesireable behaviour in our case...
		// Because we don't actually have a window, and we don't plan on calling showWindow:
		if(![self isWindowLoaded])
		{
			[super loadWindow];
		}
	}
	return self;
}

- (void)dealloc
{
	NSLog(@"Destroying %@", self);
	
	// We may have registered for stunt notifications - Don't forget to unregister for these!
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Release all retained objects
	[libraryID release];
	[librarySubscriptions release];
	[bonjourResource release];
	[xmppUserResource release];
	[socketConnector release];
	[baseURL release];
	
	[httpClient setDelegate:nil];
	[httpClient release];
	
	[data release];
	
	// Shutdown gateway server (if needed)
	if(gatewayPort > 0)
	{
		[[[NSApp delegate] helperProxy] gateway_closeServerWithLocalPort:gatewayPort];
	}
	
	// Move up the inheritance chain
	[super dealloc];
}

// SETUP AND CONFIGURATION
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
	// Setup the subscriptions table
	[subscriptionsTable setDelegate:self];
	[subscriptionsTable setAutoresizesOutlineColumn:NO];
	
	ImageAndTextCell *imageAndTextCell = [[[ImageAndTextCell alloc] init] autorelease];
	[[subscriptionsTable outlineTableColumn] setDataCell:imageAndTextCell];
}

/**
 * This method is overriden because it is undesireable in our case - we don't have any stand-alone windows.
 * The corresponding nib file only contains NSPanels that are to be used as sheets only.
**/
- (IBAction)showWindow:(id)sender
{
	// Do nothing
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)editSubscriptionsForLocalResource:(BonjourResource *)aBonjourResource
{
	// Store reference to local service
	bonjourResource = [aBonjourResource retain];
	
	// Get modifiable clone of library subscriptions
	libraryID = [[bonjourResource libraryID] copy];
	librarySubscriptions = [[[[NSApp delegate] helperProxy] subscriptionsCloneForLibrary:libraryID] retain];
	
	// The user is online, so we can download the latest XML file from them
	
	// Display subscriptions sheet
	[NSApp beginSheet:subscriptionsPanel
	   modalForWindow:dockingWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
	
	[progress setHidden:NO];
	[progress startAnimation:self];
	[progressText setHidden:NO];
	[okButton setEnabled:NO];
	[lastUpdateField setHidden:YES];
	[updateNowButton setEnabled:NO];
	
	// Start resolving their address
	[self resolveAddress];
}

- (void)editSubscriptionsForRemoteResource:(XMPPUserAndMojoResource *)aXmppUserResource
{
	// Store reference to remote service
	xmppUserResource = [aXmppUserResource retain];
	
	// Get modifiable clone of given library subscriptions
	libraryID = [[xmppUserResource libraryID] copy];
	librarySubscriptions = [[[[NSApp delegate] helperProxy] subscriptionsCloneForLibrary:libraryID] retain];
	
	// Display subscriptions sheet
	[NSApp beginSheet:subscriptionsPanel
	   modalForWindow:dockingWindow
		modalDelegate:self
	   didEndSelector:nil
		  contextInfo:nil];
	
	[progress setHidden:NO];
	[progress startAnimation:self];
	[progressText setHidden:NO];
	[okButton setEnabled:NO];
	[lastUpdateField setHidden:YES];
	[updateNowButton setEnabled:NO];
	
	// Setup a gateway (which will use the stunt protocol to connect to the remote resource)
	[self setupGateway];
}

- (void)editSubscriptionsForLibraryID:(NSString *)libID
{
	// Get modifiable clone of given library susbcriptions
	libraryID = [libID copy];
	librarySubscriptions = [[[[NSApp delegate] helperProxy] subscriptionsCloneForLibrary:libraryID] retain];
	
	[self tryCache];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method searches for a cached XML file for our library ID.
 * If one is found on disk, it is used.
 * Otherwise, the default sheet is displayed that allows users to fully unsubscribe.
**/
- (void)tryCache
{
	// See if we have a cached version of the XML file on disk
	NSString *appSupportDir = [[NSApp delegate] applicationSupportDirectory];
	
	NSString *basePath = [appSupportDir stringByAppendingPathComponent:libraryID];
	NSString *xmlPath1 = [basePath stringByAppendingPathExtension:@"xml.zlib"];
	NSString *xmlPath2 = [basePath stringByAppendingPathExtension:@"xml.gzip"];
	NSString *xmlPath3 = [basePath stringByAppendingPathExtension:@"xml"];
	
	NSString *xmlPath = nil;
	if([[NSFileManager defaultManager] fileExistsAtPath:xmlPath1])
	{
		// We found a cached compressed (zlib) XML file available on disk
		xmlPath = xmlPath1;
	}
	else if([[NSFileManager defaultManager] fileExistsAtPath:xmlPath2])
	{
		// We found a cached compressed (gzip) XML file available on disk
		xmlPath = xmlPath2;
	}
	else if([[NSFileManager defaultManager] fileExistsAtPath:xmlPath3])
	{
		// We found a cached XML file available on disk
		xmlPath = xmlPath3;
	}
	
	if(xmlPath != nil)
	{
		// Display subscriptions sheet
		[NSApp beginSheet:subscriptionsPanel
		   modalForWindow:dockingWindow
			modalDelegate:self
		   didEndSelector:nil
			  contextInfo:nil];
		
		[progress setHidden:NO];
		[progress startAnimation:self];
		[progressText setHidden:NO];
		[okButton setEnabled:NO];
		[lastUpdateField setHidden:YES];
		[updateNowButton setEnabled:NO];
		
		// Start parsing the iTunes data
		[self parseITunesData:xmlPath];
	}
	else
	{
		// There is no cached XML file available on disk - display ubsubscribe panel
		[NSApp beginSheet:unsubscribePanel
		   modalForWindow:dockingWindow
			modalDelegate:self
		   didEndSelector:nil
			  contextInfo:nil];
	}
}

/**
 * This method begins the process of resolving a bonjour service to determine it's IP address.
**/
- (void)resolveAddress
{
	// Set current status, so we know what to stop if we have to stop
	status = STATUS_XML_RESOLVING;
	
	// Update progress text
	[progressText setStringValue:NSLocalizedString(@"Resolving IP address...", @"Status")];
	
	// Start resolving the bonjour resource
	[bonjourResource resolveForSender:self];
}

/**
 * This method begins the stunt process to create a direct TCP connection to the remote service.
**/
- (void)setupGateway
{
	// Set current status, so we know what to stop if we have to stop
	status = STATUS_XML_CONNECTING;
	
	// Update progress text
	[progressText setStringValue:NSLocalizedString(@"Connecting to computer...", @"Status")];
	
	// Setup gateway server (which will use the stunt protocol to connect to the remote resource)
	
	XMPPJID *jid = [[xmppUserResource resource] jid];
	gatewayPort = [[[NSApp delegate] helperProxy] gateway_openServerForJID:jid];
	
	baseURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"http://localhost:%hu", gatewayPort]];
	
	// Even though our gateway server is always http, the remote server may be https
	if([xmppUserResource requiresTLS])
	{
		[[[NSApp delegate] helperProxy] gatewayWithLocalPort:gatewayPort setIsSecure:YES];
	}
	
	// Create HTTPClient object to handle downloading
	httpClient = [[HTTPClient alloc] init];
	
	// And start downloading the XML file
	[self downloadXML];
}

/**
 * This method begins the download of the XML file.
 * The proper XML file is requested from the server, and the status is updated.
**/
- (void)downloadXML
{
	// Set current status, so we know what to stop if we have to stop
	status = STATUS_XML_CONNECTING;
	
	// Update progress text
	[progressText setStringValue:NSLocalizedString(@"Requesting iTunes data...", @"Status")];
	
	NSString *str;
	
	if(bonjourResource)
	{
		if([bonjourResource zlibSupport])
			str = @"xml.zlib";
		else if([bonjourResource gzipSupport])
			str = @"xml.gzip";
		else
			str = @"xml";
	}
	else
	{
		if([xmppUserResource zlibSupport])
			str = @"xml.zlib";
		else if([xmppUserResource gzipSupport])
			str = @"xml.gzip";
		else
			str = @"xml";
	}
	
	NSURL *xmlURL = [NSURL URLWithString:str relativeToURL:baseURL];
	
	NSString *xmlFilePathMinusExtension = [[self libTempDir] stringByAppendingPathComponent:@"music"];
	NSString *xmlFilePath = [xmlFilePathMinusExtension stringByAppendingPathExtension:str];
	
	[httpClient setDelegate:self];
	[httpClient downloadURL:xmlURL toFile:xmlFilePath];
}

/**
 * This method begins the process of parsing the iTunes XML file.
**/
- (void)parseITunesData:(NSString *)xmlFilePath
{
	// Set the status, so we know what to cancel
	status = STATUS_XML_PARSING;
	
	// Update progress text
	[progressText setStringValue:NSLocalizedString(@"Parsing iTunes data...", @"Status")];
	
	// Start parsing iTunes Music Library in background thread
	[NSThread detachNewThreadSelector:@selector(parseITunesThread:) toTarget:self withObject:xmlFilePath];
}

/**
 * We would prefer to do most of our AppKit stuff on the main thread.
 * Sometimes things just don't work proplery if we make the method calls in a background thread.
**/
- (void)iTunesParsingDidFinish:(id)obj
{
	if(status == STATUS_XML_PARSING)
	{
		// Stop the progress animation, and hide the progress bar and the status text, and enable the OK button
		[progress stopAnimation:self];
		[progress setHidden:YES];
		[progressText setHidden:YES];
		[okButton setEnabled:YES];
		
		// Only display last update field if the user is already subscribed to something
		if([librarySubscriptions numberOfSubscribedPlaylists] > 0)
		{
			NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
			[df setFormatterBehavior:NSDateFormatterBehavior10_4];
			[df setDateStyle:NSDateFormatterShortStyle];
			[df setTimeStyle:NSDateFormatterShortStyle];
			
			NSString *localizedStr = NSLocalizedString(@"Last Update: %@", @"Update status in Subscriptions sheet");
			NSString *lastUpdateStr = [df stringFromDate:[librarySubscriptions lastSyncDate]];
			
			[lastUpdateField setHidden:NO];
			[lastUpdateField setStringValue:[NSString stringWithFormat:localizedStr, lastUpdateStr]];
			
			// Only enable the "Update Now" button if the library is currently available on the network
			if(bonjourResource || xmppUserResource)
			{
				[updateNowButton setEnabled:YES];
			}
		}
		
		// Fill the playlists table with the proper content
		[playlistsController setContent:[data iTunesPlaylists]];
	}
	else
	{
		// The user cancelled the sheet before the parsing was complete
		// We no longer have any use for the data
		[playlistsController setContent:[NSArray arrayWithObjects:nil]];
		[data release];
		data = nil;
	}
	
	// Update the status
	status = STATUS_READY;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Directories
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates (if necessary) and returns the download directory.
 * This is the directory to be used for downloading the xml file and songs.
 * 
 * This directory will be created inside the application's temporary directory.
**/
- (NSString *)libTempDir
{
	NSString *appTempDir = [[NSApp delegate] applicationTemporaryDirectory];
	NSString *libTempDir = [appTempDir stringByAppendingPathComponent:libraryID];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if([fileManager fileExistsAtPath:libTempDir] == NO)
	{
		[fileManager createDirectoryAtPath:libTempDir attributes:nil];
	}
	
	return libTempDir;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSNetService Related Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called after the NSNetService has resolved an address, or multiple addresses
**/
- (void)bonjourResource:(BonjourResource *)sender didResolveAddresses:(NSArray *)addresses
{
	DDLogVerbose(@"Did resolve: %@", [sender netServiceDescription]);
	
	// We should now have an array of addresses we can connect to.
	// Use the SocketConnector helper class to try each address in turn.
	socketConnector = [[SocketConnector alloc] initWithAddresses:addresses];
	[socketConnector start:self];
}

/**
 * Called if the net service fails to resolve any address.
 * If this happens, then we can't even contact the remote computer, and we might as well give up.
**/
- (void)bonjourResource:(BonjourResource *)sender didNotResolve:(NSDictionary *)errorDict
{
	status = STATUS_ERROR;
	
	[progress stopAnimation:self];
	[progressText setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
}

- (void)socketConnector:(SocketConnector *)sc didConnect:(AsyncSocket *)socket
{
	if(DEBUG_VERBOSE)
	{
		if([socket isIPv4]) DDLogVerbose(@"IPv4 connection");
		if([socket isIPv6]) DDLogVerbose(@"IPv6 connection");
	}
	
	// Extract baseURL from our connected socket
	NSString *basePath;
	
	if([bonjourResource requiresTLS])
	{
		if([socket isIPv4])
			basePath = [NSString stringWithFormat:@"https://%@:%hu", [socket connectedHost], [socket connectedPort]];
		else
			basePath = [NSString stringWithFormat:@"https://[%@]:%hu", [socket connectedHost], [socket connectedPort]];
	}
	else
	{
		if([socket isIPv4])
			basePath = [NSString stringWithFormat:@"http://%@:%hu", [socket connectedHost], [socket connectedPort]];
		else
			basePath = [NSString stringWithFormat:@"http://[%@]:%hu", [socket connectedHost], [socket connectedPort]];
	}
	
	DDLogVerbose(@"basePath: %@", basePath);
	
	[baseURL release];
	baseURL = [[NSURL alloc] initWithString:basePath];
	
	// Create HTTPClient object to handle downloading
	httpClient = [[HTTPClient alloc] initWithSocket:socket baseURL:baseURL];
	
	// And start downloading the XML file
	[self downloadXML];
}

- (void)socketConnectorDidNotConnect:(SocketConnector *)sc
{
	status = STATUS_ERROR;
	
	[progress stopAnimation:self];
	[progressText setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark HTTP Client Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when a password is required to connect to the mojo service.
 * We will check the keychain to see if we already know the password.
 * If we don't know the password, or the password is incorrect, we'll need to prompt the user.
**/
- (void)httpClient:(HTTPClient *)client didFailWithAuthenticationChallenge:(CFHTTPAuthenticationRef)auth
{
	// 1: First time we've had this method called
	//    A: We have the password stored in the keychain
	//    B: We don't have the password stored in they keychain
	// 2: Not the first time we've had this method called
	//    A: We need to prompt the user for the first time
	//    B: We need to prompt the user after an incorrect password
	
	BOOL promptUserForFirstTime = NO;
	BOOL promptUserAfterIncorrectPassword = NO;
	
	if(status == STATUS_XML_CONNECTING)
	{
		// This is the first time this method has been called
		// Check to see if we have a password stored in the keychain
		
		NSString *storedPassword = [RHKeychain passwordForLibraryID:[librarySubscriptions libraryID]];
		
		if(storedPassword)
		{
			[httpClient setUsername:@"anonymous" password:storedPassword];
			[httpClient downloadURL:[httpClient url] toFile:[httpClient filePath]];
		}
		else
		{
			promptUserForFirstTime = YES;
		}
	}
	else if(status == STATUS_XML_AUTHENTICATING)
	{
		// This is not the first time this method has been called
		// If the passwordField is empty we can safely assume this is the first time we've had to prompt the user
		
		if([[passwordField stringValue] length] == 0)
			promptUserForFirstTime = YES;
		else
			promptUserAfterIncorrectPassword = YES;
	}
	
	if(promptUserForFirstTime)
	{
		[progress stopAnimation:self];
		
		NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
		NSString *localizedStr = [NSString stringWithFormat:localizedFormat, [librarySubscriptions displayName]];
		[progressText setStringValue:localizedStr];
		
		[passwordField setHidden:NO];
		[subscriptionsPanel makeFirstResponder:passwordField];
		
		[okButton setEnabled:YES];
		[okButton setAction:@selector(passwordEntered:)];
	}
	else if(promptUserAfterIncorrectPassword)
	{
		[progress stopAnimation:self];
		
		NSString *localizedStr = NSLocalizedString(@"Incorrect password. Please try again:", @"Status");
		[progressText setStringValue:localizedStr];
		
		[passwordField setEnabled:YES];
		[subscriptionsPanel makeFirstResponder:passwordField];
		
		[okButton setEnabled:YES];
		[okButton setAction:@selector(passwordEntered:)];
	}
	else
	{
		[progressText setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
	}
	
	// Update the status so we know what to stop
	status = STATUS_XML_AUTHENTICATING;
}

- (void)httpClientDownloadDidBegin:(HTTPClient *)client
{
	// Update the status so we know what to stop
	status = STATUS_XML_DOWNLOADING;
	
	// We're now downloading the XML file
	[passwordField setHidden:YES];
	[progressText setStringValue:NSLocalizedString(@"Requesting iTunes data...", @"Status")];
	
	// If the user had to enter a password, store that password in the keychain automatically
	NSString *password = [passwordField stringValue];
	if([password length] > 0)
	{
		[RHKeychain setPassword:password forLibraryID:[librarySubscriptions libraryID]];
	}
}

- (void)httpClient:(HTTPClient *)client didReceiveDataOfLength:(unsigned)length
{
	// Output progress
	double percentComplete = (double)[httpClient totalBytesReceived] / (double)[httpClient fileSizeInBytes];
	int percent = (int)(percentComplete * 100);
	
	NSString *locFormat = NSLocalizedString(@"Requesting iTunes data... %i%%", @"Status");
	
	[progressText setStringValue:[NSString stringWithFormat:locFormat, percent]];
}

/**
 * Called when a download is finished.
 * The passed data is the file that was downloaded.
**/
- (void)httpClient:(HTTPClient *)client downloadDidFinish:(NSString *)filePath
{
	// Move the downloaded XML file to its permanent location
	NSString *appSupportDir = [[NSApp delegate] applicationSupportDirectory];
	
	NSString *xmlFilePathMinusExtension = [appSupportDir stringByAppendingPathComponent:libraryID];
	NSString *xmlFilePath = [xmlFilePathMinusExtension stringByAppendingPathExtension:[filePath pathExtension]];
	
	[[NSFileManager defaultManager] removeFileAtPath:xmlFilePath handler:nil];
	[[NSFileManager defaultManager] movePath:filePath toPath:xmlFilePath handler:nil];
	
	[self parseITunesData:xmlFilePath];
}

/**
 * The download failed for some reason.
 * Most likely because the computer was put to sleep, or the user quit the MojoHelper.
**/
- (void)httpClient:(HTTPClient *)httpClient didFailWithError:(NSError *)error
{
	status = STATUS_QUITTING;
	
	[progress stopAnimation:self];
	[progressText setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
}

/**
 * The download failed, due to an invalid status code (a status code other than 200).
**/
- (void)httpClient:(HTTPClient *)httpClient didFailWithStatusCode:(UInt32)statusCode
{
	status = STATUS_QUITTING;
	
	[progress stopAnimation:self];
	[progressText setStringValue:NSLocalizedString(@"Cannot fetch iTunes data", @"Status")];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Parsing:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Background thread method to parse iTunes library.
 *
 * This method is run in a separate thread.
 * It parses the iTunes music library in a background thread, allowing the GUI to remain responsive.
**/
- (void)parseITunesThread:(NSString *)xmlFilePath
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Get the downloaded data into an XML format, which may require decompression
	NSData *downloadedData = [NSData dataWithContentsOfFile:xmlFilePath options:NSUncachedRead error:nil];
	
	NSData *downloadedXMLData;
	
	if([[xmlFilePath pathExtension] hasSuffix:@"zlib"])
		downloadedXMLData = [downloadedData zlibInflate];
	else if([[xmlFilePath pathExtension] hasSuffix:@"gzip"])
		downloadedXMLData = [downloadedData gzipInflate];
	else
		downloadedXMLData = downloadedData;
	
	DDLogVerbose(@"Parsing iTunes Music Library...");
	NSDate *start = [NSDate date];
	
	data = [[ITunesForeignInfo alloc] initWithXMLData:downloadedXMLData];
	[data setLibrarySubscriptions:librarySubscriptions];
	
	NSDate *end = [NSDate date];
	DDLogVerbose(@"Done parsing (time: %f seconds)", [end timeIntervalSinceDate:start]);
	
	// We're done with our lenghthy parsing of the iTunes data.
	// Check to make sure the user didn't cancel the operation before we commit any more CPU cycles.
	if(status != STATUS_QUITTING)
	{
		// Switch over to primary thread to finish our parsing work...
		[self performSelectorOnMainThread:@selector(iTunesParsingDidFinish:) withObject:nil waitUntilDone:YES];
	}
	
    [pool release];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Interface Builder Actions:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called after the user enters a password.
 * It may be called if a user types in a password, and hits enter, or clicks the OK button.
**/
- (IBAction)passwordEntered:(id)sender
{
	NSString *password = [passwordField stringValue];
	
	// Ignore their request if they didn't type in a password
	if([password length] == 0)
	{
		return;
	}
	
	[passwordField setEnabled:NO];
	[okButton setEnabled:NO];
	[okButton setAction:@selector(ok_subscriptions:)];
	
	[progress startAnimation:self];
	[progressText setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
	
	[httpClient setUsername:@"anonymous" password:password];
	
	// Note that we don't store the password here
	// We wait for a proper authentication, and then we store it to the keychain
}

/**
 * This method is called when the user clicks the Cancel button in the subscriptions panel.
**/
- (IBAction)cancel_subscriptions:(id)sender
{
	// Close the sheet
	[subscriptionsPanel orderOut:self];
	[NSApp endSheet:subscriptionsPanel];
	
	if(status == STATUS_XML_RESOLVING)
	{
		// The user is clicking cancel while we are trying to resolve the IP address
		[bonjourResource stopResolvingForSender:self];
	}
	else if(status == STATUS_XML_CONNECTING || status == STATUS_XML_AUTHENTICATING || status == STATUS_XML_DOWNLOADING)
	{
		// The user is clicking cancel while we are downloading (or attempting to download) the XML file
		[httpClient abort];
	}
	else if(status == STATUS_XML_PARSING)
	{
		// We can't actually stop the background thread from parsing,
		// but we can prevent ourselves from doing anything after the parsing is complete.
		// This will be accomplished by observing the status variable after the parsing is complete.
	}
	
	// Update status variable to handle external processes and background threads
	status = STATUS_QUITTING;
	
	// This class is the owner of an independent nib file
	// Release self so that the nib file is released from memory
	[self autorelease];
}

/**
 * This method is called when the user clicks the OK button in the subscriptions panel.
**/
- (IBAction)ok_susbscriptions:(id)sender
{
	// Update the status so we know where we're at
	status = STATUS_FINISHING;
	
	// Luke always forgets to hit enter when he's editing stuff
	// So this little fix goes out to him, and all those people who don't know how to properly end their editing
	[subscriptionsPanel endEditingFor:subscriptionsTable];
	
	// Commit subscription changes
	[data commitSubscriptionChanges];
	
	// Close the sheet
	[subscriptionsPanel orderOut:self];
	[NSApp endSheet:subscriptionsPanel];
	
	// Post notification of changed subscriptions
	[[NSNotificationCenter defaultCenter] postNotificationName:SubscriptionsDidChangeNotification object:self];
	
	// This class is the owner of an independent nib file
	// Release self so that the nib file is released from memory
	[self autorelease];
}

/**
 * This method is called when the user clicks the "Update Now" button in the subscriptions panel.
**/
- (IBAction)updateNow_subscriptions:(id)sender
{
	// Reset the lastSyncDate, so that after we OK the changes, the subscriptions will be immediately updated
	[librarySubscriptions setLastSyncDate:[NSDate distantPast]];
	
	// Save subscriptions, close the sheet, etc...
	[self ok_susbscriptions:self];
}

/**
 * Invoked when the user clicks the total available text.
 * This allows us to toggle between long and short view for the user.
**/
- (IBAction)totalAvailableClicked:(id)sender
{
	// We want to find out if the user clicked directly on the text
	// Or if it was just a click somewhere else on the button that we can ignore
	
	// Get the location and size of the button
	NSRect viewRect = [sender bounds];
	
	// Get the size of the title
	NSSize cellSize = [[sender cell] cellSize];
	
	// Calculate the location of the centered title
	float minX = NSMidX(viewRect) - (cellSize.width / 2);
	float maxX = NSMidX(viewRect) + (cellSize.width / 2);
	float minY = NSMidY(viewRect) - (cellSize.height / 2);
	float maxY = NSMidY(viewRect) + (cellSize.height / 2);
	
	NSRect titleRect = NSMakeRect(minX, minY, maxX-minX, maxY-minY);
	
	// Get the location within the button that the user clicked
	NSPoint locationInWindow = [[NSApp currentEvent] locationInWindow];
	NSPoint locationInButton = [sender convertPoint:locationInWindow fromView:nil];
	
	if(NSPointInRect(locationInButton, titleRect))
	{
		totalAvailableUsingLongView = !totalAvailableUsingLongView;
		[self updateTotalAvailable];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSOutlineView Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)outlineView:(NSOutlineView *)outlineView
	willDisplayCell:(id)cell
	 forTableColumn:(NSTableColumn *)column
			   item:(id)item
{
	// We want to grey out the items in the myName column that aren't editable
	
	if([[column identifier] isEqualToString:COLUMNID_PLAYLIST])
	{
		// Get the actual playlist. Item is just a shadowObject from the NSTreeController
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
		ITunesPlaylist *playlist = [item valueForKey:@"observedObject"];
#else
		ITunesPlaylist *playlist = [item representedObject];
#endif
		
		// Explicitly cast cell to an ImangeAndTextCell to quite the compiler
		ImageAndTextCell *itCell = (ImageAndTextCell *)cell;
		
		if([playlist type] == PLAYLIST_TYPE_MASTER)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesLibrary"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_MUSIC)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesMusic"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_MOVIES)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesMovies"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_TVSHOWS)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesTVShows"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_PODCASTS)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesPodcasts"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_AUDIOBOOKS)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesAudiobooks"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_VIDEOS)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesVideos"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_PARTYSHUFFLE)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesPartyShuffle"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_PURCHASED)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesPurchasedMusic"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_FOLDER)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesFolder"]];
		}
		else if([playlist type] == PLAYLIST_TYPE_SMART)
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesSmartPlaylist"]];
		}
		else
		{
			[itCell setImage:[NSImage imageNamed:@"iTunesPlaylist"]];
		}
	}
	else if([[column identifier] isEqualToString:COLUMNID_MYPLAYLIST])
	{
		// Get the actual playlist. Item is just a shadowObject from the NSTreeController
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
		ITunesPlaylist *playlist = [item valueForKey:@"observedObject"];
#else
		ITunesPlaylist *playlist = [item representedObject];
#endif
		
		if([playlist isSubscribed])
			[cell setTextColor:[NSColor blackColor]];
		else
			[cell setTextColor:[NSColor grayColor]];
	}
}

/**
 * NSOutlineView Delegate method.
 * Called after the selection has changed.
 * We use this method to update the total available text.
**/
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if([subscriptionsTable selectedRow] >= 0)
	{
		[self updateTotalAvailable];
	}
	else
	{
		[totalAvailable setTitle:@""];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utility Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateTotalAvailable
{
	int index = 0;
	int numSongs = 0;
	uint64_t totalTime = 0;
	uint64_t totalSize = 0;
	
	// Get the selected playlist
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	id shadowObject2 = [subscriptionsTable itemAtRow:[subscriptionsTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject2 valueForKey:@"observedObject"];
#else
	NSTreeNode *shadowObject = [subscriptionsTable itemAtRow:[subscriptionsTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject representedObject];
#endif
	
	// Loop through every song in the playlist
	NSArray *tracks = [selectedPlaylist tracks];
	
	for(index = 0; index < [tracks count]; index++)
	{
		ITunesTrack *track = [tracks objectAtIndex:index];
		
		numSongs++;
		totalTime += [track totalTime];
		totalSize += [track fileSize];
	}
	
	NSString *count = [[NSApp delegate] getCountStr:numSongs];
	NSString *duration = [[NSApp delegate] getDurationStr:totalTime longView:totalAvailableUsingLongView];
	NSString *size = [[NSApp delegate] getSizeStr:totalSize];
	
	if(totalAvailableUsingLongView)
	{
		NSString *localizedStr = NSLocalizedString(@"%@, %@ total time, %@", @"Long view of data in iTunes");
		[totalAvailable setTitle:[NSString stringWithFormat:localizedStr, count, duration, size]];
	}
	else
	{
		[totalAvailable setTitle:[NSString stringWithFormat:@"%@, %@, %@", count, duration, size]];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Unsubscribe Panel
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called when the user clicks the Cancel button in the unsubscribe panel.
**/
- (IBAction)cancel_unsubscribe:(id)sender
{
	// Close the sheet
	[unsubscribePanel orderOut:self];
	[NSApp endSheet:unsubscribePanel];
}

/**
 * This method is called when the user clicks the Unsubscribe button in the unsubscribe panel.
**/
- (IBAction)ok_unsubscribe:(id)sender
{
	// Unsubscribe from all playlists, and commit the changes into the helperProxy
	[librarySubscriptions unsubscribeFromAllPlaylists];
	[[[NSApp delegate] helperProxy] setSubscriptions:librarySubscriptions forLibrary:[librarySubscriptions libraryID]];
	
	// Close the sheet, etc...
	[self cancel_unsubscribe:self];
	
	// Post notification of changed subscriptions
	[[NSNotificationCenter defaultCenter] postNotificationName:SubscriptionsDidChangeNotification object:self];
}

@end
