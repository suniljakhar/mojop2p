#import "MSWController.h"
#import "MojoDefinitions.h"
#import "MojoAppDelegate.h"
#import "SongProgressView.h"
#import "BonjourUtilities.h"
#import "BonjourResource.h"
#import "AsyncSocket.h"
#import "SocketConnector.h"
#import "MojoXMPP.h"
#import "HTTPClient.h"
#import "RHKeychain.h"

#import "ITunesData.h"
#import "ITunesForeignData.h"
#import "ITunesForeignInfo.h"
#import "ITunesTrack.h"
#import "ITunesPlaylist.h"
#import "ITunesPlayer.h"
#import "TracksController.h"

#import "RHURL.h"
#import "RHData.h"
#import "ImageAndTextCell.h"
#import "SrcTableHeaderCell.h"
#import "SrcTableCornerView.h"
#import "ButtonAndTextCell.h"
#import "MultiButtonLevelTextCell.h"
#import "DDSplitView.h"

// Debug levels: 0-off, 1-error, 2-warn, 3-info, 4-verbose
#ifdef CONFIGURATION_DEBUG
  #define DEBUG_LEVEL 4
#else
  #define DEBUG_LEVEL 3
#endif
#include "DDLog.h"

#define COLUMN_ALBUM_TAG          1
#define COLUMN_ARTIST_TAG         2
#define COLUMN_BITRATE_TAG        3
#define COLUMN_BPM_TAG            4
#define COLUMN_COMMENTS_TAG       5
#define COLUMN_COMPOSER_TAG       6
#define COLUMN_DATE_ADDED_TAG     7
#define COLUMN_DISC_TAG           8
#define COLUMN_GENRE_TAG          9
#define COLUMN_KIND_TAG          10
#define COLUMN_PLAYCOUNT_TAG     11
#define COLUMN_RATING_TAG        12
#define COLUMN_SIZE_TAG          13
#define COLUMN_TIME_TAG          14
#define COLUMN_TRACK_TAG         15
#define COLUMN_YEAR_TAG          16

#define MyPrivateTableViewDataType @"MyPrivateTableViewDataType"

// Declare private methods
@interface MSWController (PrivateAPI)
- (void)performPostInitSetup;
- (void)resolveAddressForXML;
- (void)setupGateway;
- (void)downloadRemoteInfo;
- (void)downloadXML;
- (void)resolveAddressForSong;
- (void)downloadSong:(ITunesTrack *)track;
- (void)downloadNextSong;
- (NSTableColumn *)tableColumnForMenuItem:(NSMenuItem *)menuItem;
- (void)updateSongTableRowWithTrack:(ITunesTrack *)track;
- (void)updateTotalAvailable;
- (NSString *)libTempDir;
- (NSString *)libPermDir;
- (NSString *)libPermBackupDir;
- (NSString *)stringWithContentsOfFile:(NSString *)filePath;
- (void)addSongWithPath:(NSString *)songPath;
- (void)openMovieInQuickTime:(ITunesTrack *)track;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation MSWController

// INIT, DEALLOC
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Disallow no arguments constructor.
**/
- (id)init
{
    [self release];
    return nil;
}

/**
 * Constructor for browsing a local service (on the local network).
**/
- (id)initWithLocalResource:(BonjourResource *)resource
{
	if((self = [super initWithWindowNibName:@"iTunesWindow"]))
	{
		// Store reference to the bonjour resource
		bonjourResource = [resource retain];
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Constructor for browsing a remote service (over XMPP).
**/
- (id)initWithRemoteResource:(XMPPUserAndMojoResource *)userResource
{
	if((self = [super initWithWindowNibName:@"iTunesWindow"]))
	{
		// Store reference to the xmpp resource
		xmppUserResource = [userResource retain];
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
}

/**
 * Constructor for browsing a service over the internet.
 * This method assumes that the given remote path is valid, and in the proper format (http://<ip>:<port>)
**/
- (id)initWithRemoteURL:(NSURL *)remoteURL
{
	if((self = [super initWithWindowNibName:@"iTunesWindow"]))
	{
		// Saved the remote path as the resolved path
		baseURL = [remoteURL copy];
		
		// Configure everything else
		[self performPostInitSetup];
	}
	return self;
	
}

- (void)performPostInitSetup
{
	// Initialize primitive variables
	gatewayPort = 0;
	
	// Create the HTTP Client
	httpClient = [[HTTPClient alloc] init];
	[httpClient setDelegate:self];
	
	// Initialize download list and related variables
	downloadList = [[NSMutableArray alloc] init];
	downloadIndex = 0;
	
	// Configure variables for displaying iTunes Data
	shortDF = [[NSDateFormatter alloc] init];
	[shortDF setFormatterBehavior:NSDateFormatterBehavior10_4];
	[shortDF setDateStyle:NSDateFormatterShortStyle];
	[shortDF setTimeStyle:NSDateFormatterShortStyle];
	
	// Set initial views
	isDisplayingArtist = YES;
	isDisplayingTotalTime = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_TOTAL_TIME];
	isDisplayingSongCount = YES;
	isDisplayingSongTime = NO;
	isDisplayingSongSize = NO;
	
	// Setup warning variables
	hasSeenLocalDownloadWarning = NO;
	isViewingLocalDownloadWarning = NO;
	tempDownloadList = [[NSMutableArray alloc] init];
	
	// Set initial status
	status = STATUS_READY;
}

/**
 * Standard Destructor.
 * Don't forget to tidy up when we're done.
**/
- (void)dealloc
{
	DDLogVerbose(@"Destroying self: %@", self);
	
	// We may have registered for stunt notifications - Don't forget to unregister for these!
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// Release normal object variables
	[bonjourResource release];
	[xmppUserResource release];
	[remoteData release];
	[socketConnector release];
	[baseURL release];
	
	[httpClient setDelegate:nil];
	[httpClient release];
	
	// Don't forget to unset the delegate for our data object before we release it
	// The reason being is that the ITunesInfo object forks off a background thread to calculated connections
	// This thread of course retains the data object, and as such the data won't get dealloced on our release...
	// And since we're it's delegate, it will try to call us when it finds a connection, and cause the app to crash
	[data setDelegate:nil];
	[data release];
	
	[player setDelegate:nil];
	[player release];
	[playerTracks release];
	[playerPlaylistPersistentID release];
	
	[downloadList release];
	[shortDF release];
	[tempDownloadList release];
	
	// Shutdown gateway server (if needed)
	if(gatewayPort > 0)
	{
		[[[NSApp delegate] helperProxy] gateway_closeServerWithLocalPort:gatewayPort];
	}
	
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// AWAKE FROM NIB, WINDOW DID LOAD, WINDOW WILL CLOSE
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)awakeFromNib
{
	// Make the column header for the source table metallic
	NSTableColumn *col = [sourceTable outlineTableColumn];
	NSString *colStr = [[col headerCell] stringValue];
	
	SrcTableHeaderCell *metalHeaderCell = [[[SrcTableHeaderCell alloc] initTextCell:colStr] autorelease];
	[col setHeaderCell:metalHeaderCell];
	
	// Register for dragging in the download table
	[downloadTable registerForDraggedTypes:[NSArray arrayWithObject:MyPrivateTableViewDataType]];
	
	// Set the autosave names for the splitviews
	// We have to do this here instead of IB as a workaround for annoying bugs
	[splitView1 setAutosaveName:@"SplitView1"];
	[splitView2 setAutosaveName:@"SplitView2"];
	
	// Collapse the download view until it's needed
	[splitView2 collapseSubview:splitView2BottomSubview];
	
	// Configure the custom slider view
	[volumeSliderView setTarget:self];
	[volumeSliderView setAction:@selector(changeVolume:)];
	
	float preferredVolume = [[NSUserDefaults standardUserDefaults] floatForKey:PREFS_PLAYER_VOLUME];
	[volumeSliderView setFloatValue:preferredVolume];
	
	// Increase intercell spacing in tables
	[songTable setIntercellSpacing:NSMakeSize(5.0F, 2.0F)];
	[downloadTable setIntercellSpacing:NSMakeSize(5.0F, 2.0F)];
	
	// Hide all but the default columns if this is the first launch
	if([[NSUserDefaults standardUserDefaults] objectForKey:@"NSTableView Columns SongTable"] == nil)
	{
		[column_bitRate setHidden:true];
		[column_bpm setHidden:true];
		[column_comments setHidden:true];
		[column_composer setHidden:true];
		[column_dateAdded setHidden:true];
		[column_disc setHidden:true];
		[column_genre setHidden:true];
		[column_kind setHidden:true];
		[column_playCount setHidden:true];
		[column_rating setHidden:true];
		[column_size setHidden:true];
		[column_year setHidden:true];
	}
	
	// Restore user preferred table column sorting
//	NSSortDescriptor *artist = [[[NSSortDescriptor alloc] initWithKey:@"artist"
//															ascending:YES
//															 selector:@selector(caseInsensitiveCompare:)] autorelease];
//	[songTable setSortDescriptors:[NSArray arrayWithObjects:artist, nil]];
	
	
	// Set the name of the window (if possible)
	if(bonjourResource)
	{
		[[self window] setTitle:[bonjourResource displayName]];
	}
	else if(xmppUserResource)
	{
		[[self window] setTitle:[xmppUserResource mojoDisplayName]];
	}
	
	// Set a tooltip for the disabled Get Songs button
	// This should help inexperienced users figure out what they're supposed to be doing
	NSString *tt;
	tt = NSLocalizedString(@"Select the songs you'd like to download", @"Tooltip for disabled Download button");
	[downloadButton setToolTip:tt];
}

- (void)windowDidLoad
{
	// Setup XML sheet (panel1)
	[panel1contentView setContentView:panel1progressView];
	
	// Display the XML Sheet (panel1)
	[NSApp beginSheet:panel1 modalForWindow:[self window] modalDelegate:self didEndSelector:nil contextInfo:nil];
	
	// We need to do one of three things here:
	// If we're browsing a local service, we need to first resolve the address
	// If we're browsing a remote service, we need to use stunt to create a connection
	// If we're browsing a service directly over the internet, we can jump right into downloading the XML file
	
	if(bonjourResource)
		[self resolveAddressForXML];
	else if(xmppUserResource)
		[self setupGateway];
	else
		[self downloadRemoteInfo];
}

- (BOOL)windowShouldClose:(id)sender
{
	if([[self window] isDocumentEdited])
	{
		[NSApp beginSheet:downloadingWarningPanel
		   modalForWindow:[self window]
			modalDelegate:self
		   didEndSelector:nil
			  contextInfo:nil];
		
		return NO;
	}
	
	return YES;
}

/**
 * Called immediately before the window closes.
 * 
 * This method's job is to release the WindowController (self)
 * This is so that the nib file is released from memory.
**/
- (void)windowWillClose:(NSNotification *)aNotification
{
	[self autorelease];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Correspondence Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//
// These methods are used to prevent multiple windows being opened for the same service.
//

- (BOOL)isLocalResource
{
	return (bonjourResource != nil);
}

- (BOOL)isRemoteResource
{
	return (xmppUserResource != nil);
}

- (NSString *)libraryID;
{
	if(data)
		return [data libraryPersistentID];
	else
	{
		if(bonjourResource)
			return [bonjourResource libraryID];
		else if(xmppUserResource)
			return [xmppUserResource libraryID];
		else
			return nil;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method begins the process of resolving an address prior to downloading XML, and configures the API and GUI.
**/
- (void)resolveAddressForXML
{
	// Set status, so we know what to stop if the user clicks the cancel button
	status = STATUS_XML_RESOLVING;
	
	// Update the GUI
	[panel1progress setIndeterminate:YES];
	[panel1progress startAnimation:self];
	[panel1text setStringValue:NSLocalizedString(@"Resolving IP address...", @"Status")];
	
	// Start resolving the bonjour service
	[bonjourResource resolveForSender:self];
}

/**
 * This method sets up a gateway server in MojoHelper.
 * This gateway will create connections as needed using the stunt/stun/turn protocols.
**/
- (void)setupGateway
{
	// Set status, so we know what to stop if the user clicks the cancel button
	status = STATUS_XML_CONNECTING;
	
	// Update the GUI
	[panel1progress setIndeterminate:YES];
	[panel1progress startAnimation:self];
	[panel1text setStringValue:NSLocalizedString(@"Connecting to computer...", @"Status")];
	
	// Setup gateway server (which will use the stunt protocol to connect to the remote resource)
	
	XMPPJID *jid = [[xmppUserResource resource] jid];
	gatewayPort = [[[NSApp delegate] helperProxy] gateway_openServerForJID:jid];
	
	baseURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"http://localhost:%hu", gatewayPort]];
	
	// Even though our gateway server is always http, the remote server may be https
	if([xmppUserResource requiresTLS])
	{
		[[[NSApp delegate] helperProxy] gatewayWithLocalPort:gatewayPort setIsSecure:YES];
	}
	
	// And now we can start downloading the XML file
	[self downloadXML];
}

/**
 * Begins the proces of downloading the info dictionary from a remote user on the internet.
**/
- (void)downloadRemoteInfo
{
	// Set current status, so we know what to stop if we have to stop
	status = STATUS_INFO_CONNECTING;
	
	// Update the GUI
	[panel1progress setIndeterminate:YES];
	[panel1progress startAnimation:self];
	[panel1text setStringValue:NSLocalizedString(@"Connecting to computer...", @"Status")];
	
	// Make HTTP request
	// Allow HTTPClient to pick a temporary file location for us
	[httpClient downloadURL:baseURL toFile:nil];
}

/**
 * Begins the process of downloading the XML file for the resolved path.
**/
- (void)downloadXML
{
	// Set current status, so we know what to stop if we have to stop
	status = STATUS_XML_CONNECTING;
	
	// Update the GUI
	[panel1progress setIndeterminate:YES];
	[panel1progress startAnimation:self];
	[panel1text setStringValue:NSLocalizedString(@"Requesting iTunes data...", @"Status")];
	
	// Setup download
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
	else if(xmppUserResource)
	{
		if([xmppUserResource zlibSupport])
			str = @"xml.zlib";
		else if([xmppUserResource gzipSupport])
			str = @"xml.gzip";
		else
			str = @"xml";
	}
	else
	{
		if([BonjourUtilities zlibSupportForTXTRecordData:remoteData])
			str = @"xml.zlib";
		else if([BonjourUtilities gzipSupportForTXTRecordData:remoteData])
			str = @"xml.gzip";
		else
			str = @"xml";
	}
	
	NSURL *xmlURL = [NSURL URLWithString:str relativeToURL:baseURL];
	
	NSString *xmlFilePathMinusExtension = [[self libTempDir] stringByAppendingPathComponent:@"music"];
	NSString *xmlFilePath = [xmlFilePathMinusExtension stringByAppendingPathExtension:str];
	
	// Make HTTP request
	[httpClient downloadURL:xmlURL toFile:xmlFilePath];
}

/**
 * This method begins the process of resolving an address prior to downloading songs,
 * and configures the API and GUI.
**/
- (void)resolveAddressForSong
{
	// Set status, so we know what to stop if the user clicks the cancel button
	status = STATUS_SONG_RESOLVING;
	
	// Start resolving the bonjour service
	[bonjourResource resolveForSender:self];
}

/**
 * This method gets the API ready to start downloading songs.
 * To do so it must reset all the necessary variables, and populate the getSongList arrray.
**/
- (void)downloadSong:(ITunesTrack *)track
{
	
}

/**
 * This method may be called to initialize the download for the next song in the list.
 * It assumes that the getSongList, and associated variables, are configured and correct.
**/
- (void)downloadNextSong
{
	// Set status, so we know what to stop if the user clicks the cancel button
	status = STATUS_SONG_CONNECTING;
	
	// Get the current track that we're downloading
	int trackID = [[downloadList objectAtIndex:downloadIndex] intValue];
	ITunesTrack *track = [data iTunesTrackForID:trackID];
	
	// Setup the download request
	NSString *relativePath = [NSString stringWithFormat:@"%i/%@", [track trackID], [track persistentID]];
	NSURL *songURL = [NSURL URLWithString:relativePath relativeToURL:baseURL];
	
	NSString *songPath = [[self libTempDir] stringByAppendingPathComponent:[track persistentID]];
	
	// Start the download
	[httpClient downloadURL:songURL toFile:songPath];
	
	// Update the track status
	[track setDownloadStatus:DOWNLOAD_STATUS_DOWNLOADING];
	
	// Update the download table
	[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
	
	// Put a black dot in the close button
	[[self window] setDocumentEdited:YES];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSNetService Related Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called after the NSNetService has resolved an address
**/
- (void)bonjourResource:(BonjourResource *)sender didResolveAddresses:(NSArray *)addresses
{
	DDLogVerbose(@"Did resolve: %@", [sender netServiceDescription]);
	
	// Update GUI
	[panel1text setStringValue:NSLocalizedString(@"Connecting to computer...", @"Status")];
	
	// Set the status to allow the user to dismiss the sheet
	if(status == STATUS_XML_RESOLVING)
		status = STATUS_XML_CONNECTING;
	else
		status = STATUS_SONG_CONNECTING;
	
	[socketConnector release];
	socketConnector = [[SocketConnector alloc] initWithAddresses:addresses];
	[socketConnector start:self];
}

/**
 * Called if the NSNetService fails to resolve any address.
 * If this happens, then we can't even contact the computer, and we might as well give up.
**/
- (void)bonjourResource:(BonjourResource *)sender didNotResolve:(NSDictionary *)errorDict
{
	if(status == STATUS_XML_RESOLVING)
	{
		// Display error message to user
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else
	{
		// Update the track
		int trackID = [[downloadList objectAtIndex:downloadIndex] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		[track setDownloadStatus:DOWNLOAD_STATUS_FAILED];
		
		// Update the downloadList
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
		
		// Update the general status
		status = STATUS_ERROR;
	}
}

- (void)socketConnector:(SocketConnector *)sc didConnect:(AsyncSocket *)socket
{
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
	
	// Reconfigure HTTPClient to use the newly connected socket
	[httpClient setSocket:socket baseURL:baseURL];
	
	if(status == STATUS_XML_CONNECTING)
	{
		[self downloadXML];
	}
	else if(status == STATUS_SONG_CONNECTING)
	{
		[self downloadNextSong];
	}
}

- (void)socketConnectorDidNotConnect:(SocketConnector *)sc
{
	if(status == STATUS_XML_CONNECTING)
	{
		// Display error message to user
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else
	{
		// Update the track
		int trackID = [[downloadList objectAtIndex:downloadIndex] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		[track setDownloadStatus:DOWNLOAD_STATUS_FAILED];
		
		// Update the downloadList
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
		
		// Update the general status
		status = STATUS_ERROR;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark HTTP Client Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called when a password is required to connect to the mojo service.
 * We will check the keychain to see if we already know the password.
 * If we don't know the password, or the password is incorrect, we'll need to prompt the user.
**/
- (void)httpClient:(HTTPClient *)client didFailWithAuthenticationChallenge:(CFHTTPAuthenticationRef)auth
{
	BOOL panel1_promptUserForFirstTime = NO;
	BOOL panel1_promptUserAfterIncorrectPassword = NO;
	
	BOOL panel2_promptUserForFirstTime = NO;
	BOOL panel2_promptUserAfterIncorrectPassword = NO;
	
	if(status == STATUS_XML_CONNECTING)
	{
		// This is the first time we've been prompted for a password
		// Check to see if we have a password stored in the keychain
		
		NSString *libID;
		if(bonjourResource)
			libID = [bonjourResource libraryID];
		else if(xmppUserResource)
			libID = [xmppUserResource libraryID];
		else
			libID = [BonjourUtilities libraryIDForTXTRecordData:remoteData];
		
		NSString *storedPassword = [RHKeychain passwordForLibraryID:libID];
		
		if(storedPassword)
		{
			[httpClient setUsername:@"anonymous" password:storedPassword];
			[httpClient downloadURL:[httpClient url] toFile:[httpClient filePath]];
			
			[panel1text setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
		}
		else
		{
			panel1_promptUserForFirstTime = YES;
		}
		
		// Update the status so we know what's going on
		status = STATUS_XML_AUTHENTICATING;
	}
	else if(status == STATUS_XML_AUTHENTICATING)
	{
		// This is not the first time we've been prompted for a password
		// If the passwordField is empty we can safely assume this is the first time we've had to prompt the user
		
		if([[panel1passwordField stringValue] length] == 0) {
			panel1_promptUserForFirstTime = YES;
		}
		else {
			panel1_promptUserAfterIncorrectPassword = YES;
		}
	}
	else if(status == STATUS_SONG_CONNECTING)
	{
		// This is the first time we've been prompted for a password
		// Check to see if we have a password stored in the keychain
		
		NSString *libID;
		if(bonjourResource)
			libID = [bonjourResource libraryID];
		else if(xmppUserResource)
			libID = [xmppUserResource libraryID];
		else
			libID = [BonjourUtilities libraryIDForTXTRecordData:remoteData];
		
		NSString *storedPassword = [RHKeychain passwordForLibraryID:libID];
		
		if(storedPassword) {
			[httpClient setUsername:@"anonymous" password:storedPassword];
			[panel2text setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
		}
		else {
			panel2_promptUserForFirstTime = YES;
		}
		
		// Update the status so we know what's going on
		status = STATUS_SONG_AUTHENTICATING;
	}
	else if(status == STATUS_SONG_AUTHENTICATING)
	{
		// This is not the first time we've been prompted for a password
		// If the passwordField is empty we can safely assume this is the first time we've had to prompt the user
		
		if([[panel2passwordField stringValue] length] == 0) {
			panel2_promptUserForFirstTime = YES;
		}
		else {
			panel2_promptUserAfterIncorrectPassword = YES;
		}
	}
	
	if(panel1_promptUserForFirstTime)
	{
		[panel1contentView setContentView:panel1authenticationView];
		
		[panel1passwordField setEnabled:YES];
		[panel1passwordImage setEnabled:YES];
		[panel1savePasswordButton setEnabled:YES];
		
		NSString *localizedStr;
		
		if(bonjourResource)
		{
			NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
			localizedStr = [NSString stringWithFormat:localizedFormat, [bonjourResource displayName]];
		}
		else if(xmppUserResource)
		{
			NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
			localizedStr = [NSString stringWithFormat:localizedFormat, [xmppUserResource mojoDisplayName]];
		}
		else
		{
			if(remoteData)
			{
				NSString *shareName = [BonjourUtilities shareNameForTXTRecordData:remoteData];
				
				// Generally, the shareName should never be nil or an empty string
				// What Mojo does is set the shareName to the computer name prior to publishing it, if the user
				// has not configured a specific share name for their library.
				// However, this was not the case in pre 1.1 versions,
				// and may not be the case in alternate implementations.
				
				if((shareName != nil) && ([shareName length] > 0))
				{
					NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
					localizedStr = [NSString stringWithFormat:localizedFormat, shareName];
				}
				else
				{
					localizedStr = NSLocalizedString(@"Enter password for remote computer:", @"Status");
				}
			}
			else
			{
				localizedStr = NSLocalizedString(@"Enter password for remote computer:", @"Status");
			}
		}
		
		[panel1text setStringValue:localizedStr];
		[panel1 makeFirstResponder:panel1passwordField];
	}
	else if(panel1_promptUserAfterIncorrectPassword)
	{
		[panel1passwordField setEnabled:YES];
		[panel1passwordImage setEnabled:YES];
		[panel1savePasswordButton setEnabled:YES];
		
		NSString *localizedStr = NSLocalizedString(@"Incorrect password. Please try again:", @"Status");
		
		[panel1text setStringValue:localizedStr];
		[panel1 makeFirstResponder:panel1passwordField];
	}
	else if(panel2_promptUserForFirstTime)
	{
		// Display the Song Sheet (panel2)
		[NSApp beginSheet:panel2 modalForWindow:[self window] modalDelegate:self didEndSelector:nil contextInfo:nil];
				
		[panel2passwordField setEnabled:YES];
		[panel2passwordImage setEnabled:YES];
		[panel2savePasswordButton setEnabled:YES];
		
		NSString *localizedStr;
		
		if(bonjourResource)
		{
			NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
			localizedStr = [NSString stringWithFormat:localizedFormat, [bonjourResource displayName]];
		}
		else if(xmppUserResource)
		{
			NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
			localizedStr = [NSString stringWithFormat:localizedFormat, [xmppUserResource mojoDisplayName]];
		}
		else
		{
			if(remoteData)
			{
				NSString *shareName = [BonjourUtilities shareNameForTXTRecordData:remoteData];
				
				// Generally, the shareName should never be nil or an empty string
				// What Mojo does is set the shareName to the computer name prior to publishing it, if the user
				// has not configured a specific share name for their library.
				// However, this was not the case in pre 1.1 versions,
				// and may not be the case in alternate implementations.
				
				if((shareName != nil) && ([shareName length] > 0))
				{
					NSString *localizedFormat = NSLocalizedString(@"Enter password for \"%@\":", @"Status");
					localizedStr = [NSString stringWithFormat:localizedFormat, shareName];
				}
				else
				{
					localizedStr = NSLocalizedString(@"Enter password for remote computer:", @"Status");
				}
			}
			else
			{
				localizedStr = NSLocalizedString(@"Enter password for remote computer:", @"Status");
			}
		}
		
		[panel2text setStringValue:localizedStr];
		[panel2 makeFirstResponder:panel2passwordField];
	}
	else if(panel2_promptUserAfterIncorrectPassword)
	{
		[panel2passwordField setEnabled:YES];
		[panel2passwordImage setEnabled:YES];
		[panel2savePasswordButton setEnabled:YES];
		
		NSString *localizedStr = NSLocalizedString(@"Incorrect password. Please try again:", @"Status");
		
		[panel2text setStringValue:localizedStr];
		[panel2 makeFirstResponder:panel2passwordField];
	}
}	

/**
 * This method is called when an HTTPClient has started receiving the contents of a file being downloaded.
**/
- (void)httpClientDownloadDidBegin:(HTTPClient *)client
{
	if(status == STATUS_INFO_CONNECTING)
	{
		// Update progress text field
		NSString *localizedStr = NSLocalizedString(@"Requesting service info...", @"Status");
		[panel1text setStringValue:localizedStr];
		
		// We're going to keep an indeterminate progress bar for the txt record since it's only a few bytes
		
		// Update status - We're moving from connecting to downloading
		status = STATUS_INFO_DOWNLOADING;
	}
	else if(status == STATUS_XML_CONNECTING || status == STATUS_XML_AUTHENTICATING)
	{
		// Hide password stuff and store password if necessary
		if(status == STATUS_XML_AUTHENTICATING)
		{
			[panel1contentView setContentView:panel1progressView];
			
			// Save info in keychain if needed
			if([panel1savePasswordButton state] == NSOnState)
			{
				// We may not have prompted the user if we already had the password in the keychain
				if([[panel1passwordField stringValue] length] > 0)
				{
					NSString *libID;
					if(bonjourResource)
						libID = [bonjourResource libraryID];
					else if(xmppUserResource)
						libID = [xmppUserResource libraryID];
					else
						libID = [BonjourUtilities libraryIDForTXTRecordData:remoteData];
					
					[RHKeychain setPassword:[panel1passwordField stringValue] forLibraryID:libID];
				}
			}
		}
		
		// Update progress text field (not necessary, but here in case we decide to change our wording)
		NSString *localizedStr = NSLocalizedString(@"Requesting iTunes data...", @"Status");
		[panel1text setStringValue:localizedStr];
		
		// Start a determinate progress bar at 0%
		// Notice that the order of the steps below is important
		[panel1progress stopAnimation:self];
		[panel1progress setIndeterminate:NO];
		[panel1progress setDoubleValue:0];
		
		// Update status - We're moving from connecting to downloading
		status = STATUS_XML_DOWNLOADING;
	}
	else if(status == STATUS_SONG_CONNECTING || status == STATUS_SONG_AUTHENTICATING)
	{
		// Hide password stuff and store password if necessary
		if(status == STATUS_SONG_AUTHENTICATING)
		{
			// Save info in keychain if needed
			if([panel2savePasswordButton state] == NSOnState)
			{
				// We may not have prompted the user if we already had the password in the keychain
				if([[panel2passwordField stringValue] length] > 0)
				{
					NSString *libID;
					if(bonjourResource)
						libID = [bonjourResource libraryID];
					else if(xmppUserResource)
						libID = [xmppUserResource libraryID];
					else
						libID = [BonjourUtilities libraryIDForTXTRecordData:remoteData];
					
					[RHKeychain setPassword:[panel2passwordField stringValue] forLibraryID:libID];
				}
			}
			
			// If we had to authenticate for a song, that means that a password was added or changed.
			// This means we'll also want to update the iTunesPlayer.
			[player setUsername:[httpClient username] password:[httpClient password]];
			
			// Dismiss the sheet
			[panel2 orderOut:self];
			[NSApp endSheet:panel2];
		}
		
		// Update the download table
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
		
		// Update status - We're moving from connecting to downloading (if this is the first song in the list)
		status = STATUS_SONG_DOWNLOADING;
	}
}

/**
 * This method is called when an HTTPClient has started receiving part of the contents of a file being downloaded.
 * The passed length is the size of the data received during this iteration of the download.
 * We can get the total amount downloaded, and the total size of the download from httpClient methods.
**/
- (void)httpClient:(HTTPClient *)client didReceiveDataOfLength:(unsigned)length
{
	if(status == STATUS_INFO_DOWNLOADING)
	{
		// We're going to keep an indeterminate progress bar for this step since it should be very short
	}
	else if(status == STATUS_XML_DOWNLOADING)
	{
		// Update the progress bar
		double percentComplete = (double)[httpClient progress];
		[panel1progress setDoubleValue:(percentComplete * 100)];
	}
	else if(status == STATUS_SONG_DOWNLOADING)
	{
		// Update the download table
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
	}
}

/**
 * Sent when an HTTPClient has completed downloading successfully.
**/
- (void)httpClient:(HTTPClient *)client downloadDidFinish:(NSString *)filePath
{
	if(status == STATUS_INFO_DOWNLOADING)
	{
		// We just finished downloading the txtRecordData from the remote service
		// It should be very small, so we'll store it in RAM for quick access
		remoteData = [[NSData alloc] initWithContentsOfFile:filePath];
		
		// Update the window title
		NSString *shareName = [BonjourUtilities shareNameForTXTRecordData:remoteData];
		
		if((shareName != nil) && ![shareName isEqualToString:@""])
		{
			[[self window] setTitle:shareName];
		}
		
		// Start downloading the XML file
		[self downloadXML];
	}
	else if(status == STATUS_XML_DOWNLOADING)
	{
		// Set status, so we know what to stop if the user clicks the cancel button
		status = STATUS_XML_PARSING;
		
		// Update progress information
		[panel1progress setIndeterminate:YES];
		[panel1progress startAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Parsing iTunes data...", @"Status")];
		
		// Move the downloaded XML file to its permanent location
		NSString *appSupportDir = [[NSApp delegate] applicationSupportDirectory];
		
		NSString *xmlFilePathMinusExtension = [appSupportDir stringByAppendingPathComponent:[self libraryID]];
		NSString *xmlFilePath = [xmlFilePathMinusExtension stringByAppendingPathExtension:[filePath pathExtension]];
		
		[[NSFileManager defaultManager] removeFileAtPath:xmlFilePath handler:nil];
		[[NSFileManager defaultManager] movePath:filePath toPath:xmlFilePath handler:nil];
		
		// Start parsing iTunes Music Library in background thread
		[NSThread detachNewThreadSelector:@selector(parseITunesThread:) toTarget:self withObject:xmlFilePath];
		
		// Note that Cocoa's thread management system retains the target during the execution of the detached thread
		// When the thread terminates, the target gets released
		// Thus, the target's dealloc cannot be called until after this thread is completed
		
		// Note that Cocoa's thread management system also retains the object during the execution of the thread
	}
	else if(status == STATUS_SONG_DOWNLOADING)
	{
		// Move the downloaded song within iTunes' music directory
		
		int trackID = [[downloadList objectAtIndex:downloadIndex] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		NSString *extension = [track pathExtension];
		
		NSMutableString *baseFilename = [NSMutableString stringWithCapacity:50];
		if([[track artist] length] > 0)
		{
			if([[track name] length] > 0)
				[baseFilename appendFormat:@"%@ - %@", [track artist], [track name]];
			else
				[baseFilename appendFormat:@"%@ - %@", [track artist], [track persistentID]];
		}
		else
		{
			if([[track name] length] > 0)
				[baseFilename appendFormat:@"%@", [track name]];
			else
				[baseFilename appendFormat:@"%@", [track persistentID]];
		}
		
		// Replace illegal filename characters
		// Note: Mac OS X will automatically interpret ':' as '/' when displaying in the finder
		
		[baseFilename replaceOccurrencesOfString:@":"
								  withString:@"_"
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [baseFilename length])];
		
		[baseFilename replaceOccurrencesOfString:@"/"
								  withString:@":"
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [baseFilename length])];
		
		NSString *filename = [baseFilename stringByAppendingPathExtension:extension];
		
		NSString *songPath = [[self libPermDir] stringByAppendingPathComponent:filename];
		
		unsigned index = 1;
		while([[NSFileManager defaultManager] fileExistsAtPath:songPath])
		{
			filename = [NSString stringWithFormat:@"%@-%u.%@", baseFilename, index++, extension];
			
			songPath = [[self libPermDir] stringByAppendingPathComponent:filename];
		}
		
		// Check to make sure the original file isn't a 0 byte file.
		unsigned long long fSize = 0;
		fSize = [[[NSFileManager defaultManager] fileAttributesAtPath:filePath traverseLink:NO] fileSize];
		
		DDLogInfo(@"Downloaded file size = %qu", fSize);
		
		DDLogInfo(@"movePath:\"%@\"", filePath);
		DDLogInfo(@"  toPath:\"%@\"", songPath);
			
		BOOL wasMoved = [[NSFileManager defaultManager] movePath:filePath toPath:songPath handler:nil];
		
		if(!wasMoved)
		{
			DDLogError(@"Failed to move file! Switching to backup plan...");
			
			// Backup Plan - It seems like external hard drives may cause the move operation to fail
			
			songPath = [[self libPermBackupDir] stringByAppendingPathComponent:filename];
			
			DDLogInfo(@"movePath:\"%@\"", filePath);
			DDLogInfo(@"  toPath:\"%@\"", songPath);
			
			wasMoved = [[NSFileManager defaultManager] movePath:filePath toPath:songPath handler:nil];
			
			if(!wasMoved)
			{
				DDLogError(@"Failed to move downloaded file to backup directory!");
			}
		}
		
		// Add the song to iTunes via AppleScript
		[self addSongWithPath:songPath];
		
		// Add empty connection to the track so it becomes grayed out
		[track setHasLocalConnection:YES];
		
		// Update track
		[track setDownloadStatus:DOWNLOAD_STATUS_DOWNLOADED];
		
		// Update downloadTable
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
		
		// Update songTable
		[self updateSongTableRowWithTrack:track];
		
		// Increment the downloadIndex counter
		downloadIndex++;
		
		if(downloadIndex < [downloadList count])
		{
			// There are more songs to download
			[self downloadNextSong];
		}
		else
		{
			// Update status
			status = STATUS_READY;
			
			// Remove the black dot from the close button
			[[self window] setDocumentEdited:NO];
		}
	}
}

/**
 * Sent if the download fails for some reason.
 * Generally this will be because the remote computer went to sleep, or closed MojoHelper.
**/
- (void)httpClient:(HTTPClient *)client didFailWithError:(NSError *)error
{
	DDLogError(@"MSWController: httpClient:didFailWithError: %@", error);
	
	if(status == STATUS_INFO_CONNECTING)
	{
		// Display error message to user.
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else if(status == STATUS_INFO_DOWNLOADING)
	{
		// Display error message to user.
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot fetch service info", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else if(status == STATUS_XML_CONNECTING || status == STATUS_XML_AUTHENTICATING)
	{
		// Display error message to user.
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot connect to computer", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else if(status == STATUS_XML_DOWNLOADING)
	{
		// Display error message to user.
		[panel1progress stopAnimation:self];
		[panel1text setStringValue:NSLocalizedString(@"Cannot fetch iTunes data", @"Status")];
		
		// Display try again button
		[panel1helpButton setHidden:NO];
		[panel1tryAgainButton setHidden:NO];
		[panel1tryAgainButton setEnabled:YES];
		
		// Set the status to allow the user to dismiss the sheet
		status = STATUS_ERROR;
	}
	else
	{
		// Update the track
		int trackID = [[downloadList objectAtIndex:downloadIndex] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		[track setDownloadStatus:DOWNLOAD_STATUS_FAILED];
		
		// Update the downloadList
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:downloadIndex]];
		
		// Increment the downloadIndex counter
		downloadIndex++;
		
		// Move on to the next song in the list if possible
		if(downloadIndex < [downloadList count])
		{
			// There are more songs to download
			[self downloadNextSong];
		}
		else
		{
			// Update status
			status = STATUS_READY;
			
			// Remove the black dot from the close button
			[[self window] setDocumentEdited:NO];
		}
	}
}

- (void)httpClient:(HTTPClient *)client didFailWithStatusCode:(UInt32)statusCode
{
	DDLogError(@"MSWController: httpClient:didFailWithStatusCode: %i", statusCode);
	
	NSError *httpError = [NSError errorWithDomain:@"HTTPErrorDomain" code:statusCode userInfo:nil];
	
	// We treat this as the equivalent of an error
	[self httpClient:httpClient didFailWithError:httpError];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iTunes Parsing
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
	
	// Parse iTunesData
	data = [[ITunesForeignInfo alloc] initWithXMLData:downloadedXMLData];
	
	NSDate *end = [NSDate date];
	DDLogVerbose(@"Done parsing (time: %f seconds)", [end timeIntervalSinceDate:start]);
	
	// We're done with our lenghthy parsing of the iTunes data.
	// Check to make sure the user didn't cancel the operation before we commit any more CPU cycles.
	if(status != STATUS_QUITTING)
	{
		// Switch over to primary thread to finish our parsing work...
		[self performSelectorOnMainThread:@selector(iTunesParsingDidFinish:) withObject:nil waitUntilDone:NO];
		
		// Start calculating the song connections (in the current background thread)
		[data setDelegate:self];
		[data calculateConnections];
	}
	
    [pool release];
}

/**
 * We would prefer to do most of our AppKit stuff on the main thread.
 * Sometimes things just don't work proplery if we make the method calls in a background thread.
**/
- (void)iTunesParsingDidFinish:(id)obj
{
	// Stop the animation
	[panel1progress stopAnimation:self];
	[panel1text setStringValue:NSLocalizedString(@"Done", @"Status")];
	
	// Setup iTunesPlayer
	if(xmppUserResource)
	{
		player = [[ITunesPlayer alloc] initWithBaseURL:baseURL isGateway:YES];
	}
	else
	{
		player = [[ITunesPlayer alloc] initWithBaseURL:baseURL isGateway:NO];
	}
	[player setDelegate:self];
	[player setVolume:[volumeSliderView floatValue]];
	
	// Our HTTPClient takes care of authentication for us.
	// But the iTunesPlayer needs to configure a gateway server to do it.
	if([httpClient username] && [httpClient password])
	{
		[player setUsername:[httpClient username] password:[httpClient password]];
	}
	
	// Setup SongProgressView
	[lcdSongProgressView setITunesPlayer:player];
	
	// Setup playlist subscriptions
	// We do this here because DO must be preformed on the primary thread
	id helperProxy = [[NSApp delegate] helperProxy];
	LibrarySubscriptions *ls = [helperProxy subscriptionsCloneForLibrary:[data libraryPersistentID]];
	
	[data setLibrarySubscriptions:ls];
	
	// Setup source and song table
	
	// Set self as the delegate so we can control display aspects, and properly update when the tables change
	[sourceTable setDelegate:self];
	[songTable setDelegate:self];
	
	// Fill the controller with the proper content
	[playlistsController setContent:[data iTunesPlaylists]];
	
	// Update the available text field
	[self updateTotalAvailable];
	
	// Dismiss the sheet
	[panel1 orderOut:self];
	[NSApp endSheet:panel1];
	
	// Update status
	status = STATUS_READY;
	
	// Ugly Hack
	// For some reason, songTable's scrollview thinks it's displaying a horizontal scrollbar even when it's not.
	// The consequence of this is the vertical scrollbar is always raised up off the bottom.
	// When there isn't a horizontal scrollbar this looks really odd.
	// The problem disappears when the user resizes the view in any manner.
	// We force a tiny resize here to make it look correct immediately.
	NSScrollView *songScrollView = (NSScrollView *)[[songTable superview] superview];
	NSRect oldFrame = [songScrollView frame];
	NSRect newFrame = oldFrame;
	newFrame.size.height -= 1;
	
	[songScrollView setFrame:newFrame];
	[songScrollView setFrame:oldFrame];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Menu Item Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This is a rather primitive method to get the table column that a menu item is referring to.
 * A better way would be to setup these connections in interface builder or something.
 * But at the time of this writing, I don't believe this is possible.
 * So to get the job done, each menuItem has been given a unique tag, and the tags are similary defined in this file.
 * This means that if you change one, you have to update the other.
 * Like I said, not an optimal solution, but it's the only idea I have for right now.
**/
- (NSTableColumn *)tableColumnForMenuItem:(NSMenuItem *)menuItem
{	
	if([menuItem tag] == COLUMN_ALBUM_TAG)      return column_album;
	if([menuItem tag] == COLUMN_ARTIST_TAG)     return column_artist;
	if([menuItem tag] == COLUMN_BITRATE_TAG)    return column_bitRate;
	if([menuItem tag] == COLUMN_BPM_TAG)        return column_bpm;
	if([menuItem tag] == COLUMN_COMMENTS_TAG)   return column_comments;
	if([menuItem tag] == COLUMN_COMPOSER_TAG)   return column_composer;
	if([menuItem tag] == COLUMN_DATE_ADDED_TAG) return column_dateAdded;
	if([menuItem tag] == COLUMN_DISC_TAG)       return column_disc;
	if([menuItem tag] == COLUMN_GENRE_TAG)      return column_genre;
	if([menuItem tag] == COLUMN_KIND_TAG)       return column_kind;
	if([menuItem tag] == COLUMN_PLAYCOUNT_TAG)  return column_playCount;
	if([menuItem tag] == COLUMN_RATING_TAG)     return column_rating;
	if([menuItem tag] == COLUMN_SIZE_TAG)       return column_size;
	if([menuItem tag] == COLUMN_TIME_TAG)       return column_time;
	if([menuItem tag] == COLUMN_TRACK_TAG)      return column_track;
	if([menuItem tag] == COLUMN_YEAR_TAG)       return column_year;
	
	return nil;
}

/**
 * Here's how menu items work:
 * Each menu item has a specified action.
 * If the first responder (eg key window) responds to that specified action, the menu item can become enabled.
 * It will be automatically enabled, unless the first responder has the validateMenuItem: method.
 * In this case, the menu item will only be enabled if the validateMenuItem: method says it can be.
 * We currenly have no need to disable any menu items, but we do have a need to set the state of particular menu items.
 * We need to set the state of the menu items for adding and removing table columns.
 * I don't want to have to do this manually, because the songTable has an autosaveName,
 * so it automatically configures itself when the nib is being setup.
 * So instead, I use this method to properly set the state of any menu item that needs it.
**/
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if([menuItem action] == @selector(addRemoveColumn:))
	{
		NSTableColumn *column = [self tableColumnForMenuItem:menuItem];
		if(column != nil)
		{
			[menuItem setState:([column isHidden]) ? NSOffState : NSOnState];
		}
	}
	
	return YES;
}

- (IBAction)addRemoveColumn:(id)sender
{
	NSTableColumn *column = [self tableColumnForMenuItem:sender];
	
	if(column != nil)
	{
		if([column isHidden])
			[column setHidden:false];
		else
			[column setHidden:true];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Interface Builder Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)passwordEnteredForLoad:(id)sender
{
	NSString *password = [panel1passwordField stringValue];
	
	// Ignore their request if they didn't type in a password
	if([password length] == 0)
	{
		return;
	}
	
	[panel1passwordField setEnabled:NO];
	[panel1passwordImage setEnabled:NO];
	[panel1savePasswordButton setEnabled:NO];
	[panel1text setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
	
	[httpClient setUsername:@"anonymous" password:password];
}

/**
 * The connection attempt failed for some reason, and the user clicked the help button.
**/
- (IBAction)helpLoad:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:MOJO_URL_TROUBLESHOOT]];
}

/**
 * The connection attempt failed for some reason, and the user clicked the try again button.
**/
- (IBAction)tryAgainLoad:(id)sender
{
	if(status == STATUS_ERROR)
	{
		// Disable button
		[panel1tryAgainButton setEnabled:NO];
		
		// We need to do one of three things here:
		// If we're browsing a local service, we need to first resolve the address
		// If we're browsing a remote service, we need to use stunt to create a connection
		// If we're browsing a service directly over the internet, we can jump right into downloading the XML file
		
		if(bonjourResource)
			[self resolveAddressForXML];
		else if(xmppUserResource)
			[self downloadXML];
		else
			[self downloadRemoteInfo];
	}
}

/**
 * This method is called when the user clicks the "Cancel" button while we are loading the XML file.
 * We attempt to cancel the load, and ultimately close the window.
**/
- (IBAction)cancelLoad:(id)sender
{
	if(status == STATUS_ERROR)
	{
		// The user is clicking Cancel after an error occured
		// Nothing to do here but to allow the window to be closed...
	}
	else if(status == STATUS_INFO_CONNECTING || status == STATUS_INFO_DOWNLOADING)
	{
		// The user is clicking cancel while we are downloading (or attempting to download) the txt record
		[httpClient abort];
	}
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
	else
	{
		// We can't actually stop the background thread from parsing,
		// but we can prevent ourselves from doing anything after the parsing is complete.
		// This will be accomplished by observing the status variable after the parsing is complete.
	}
	
	// Update status variable to handle external processes and background threads
	status = STATUS_QUITTING;
	
	// Dismiss the sheet, and close the window
	[panel1 orderOut:self];
	[NSApp endSheet:panel1];
	[[self window] close];
}

- (IBAction)passwordEnteredForDownload:(id)sender
{
	NSString *password = [panel2passwordField stringValue];
	
	// Ignore their request if they didn't type in a password
	if([password length] == 0)
	{
		return;
	}
	
	[panel2passwordField setEnabled:NO];
	[panel2passwordImage setEnabled:NO];
	[panel2savePasswordButton setEnabled:NO];
	[panel2text setStringValue:NSLocalizedString(@"Authenticating...", @"Status")];
	
	[httpClient setUsername:@"anonymous" password:password];
}

/**
 * Called when the user clicks the "Cancel" button while we are downloading songs.
 * We attempt to cancel the downloads, and close the sheet.
**/
- (IBAction)cancelDownload:(id)sender
{
	if(status == STATUS_ERROR)
	{
		// The user is clicking Cancel after an error occured
	}
	else if(status == STATUS_SONG_RESOLVING)
	{
		// The user is clicking cancel while we are trying to resolve the IP address
		[bonjourResource stopResolvingForSender:self];
	}
	else if(status == STATUS_SONG_CONNECTING ||
			status == STATUS_SONG_AUTHENTICATING || status == STATUS_SONG_DOWNLOADING)
	{
		// The user is clicking cancel while we are downloading (or attempting to download) the XML file
		[httpClient abort];
	}
	
	if(sender != self)
	{
		// Dismiss the sheet
		// The panel2 sheet is present because the user was prompted for a password
		[panel2 orderOut:self];
		[NSApp endSheet:panel2];
	}
}

/**
 * Called when the user clicks the "Download" button.
 * This method adds all selected songs to the download list, and begins the download process if necessary.
**/
- (IBAction)downloadSelected:(id)sender
{
	NSIndexSet *selectedRows = [songTable selectedRowIndexes];
	
	unsigned int selectedRow = [selectedRows firstIndex];
	while(selectedRow != NSNotFound)
	{
		// Get the track that's currently selected in the table
		ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:selectedRow];
		
		// Add the track to the download list
		// This will also handle updating the track download status
		[self downloadSong:track];
		
		// Note: the above method does not handle updating and GUI elements
		// Thus we still need to update the tables
		
		// If we call [songTable reloadData] we would update all visible rows
		// So instead we are going to tell the songTable to only update the row of the updated track
		[songTable setNeedsDisplayInRect:[songTable rectOfRow:selectedRow]];
		
		// Get the next selected row
		selectedRow = [selectedRows indexGreaterThanIndex:selectedRow];
	}
	
	// Update the download table
	[downloadTable reloadData];
}

/**
 * If the user attempts to download music from their own library we display a warning message to the effect of:
 * This action will result in you having duplicate songs in your iTunes library. Are you sure you want to do this?
 * 
 * If the user clicks cancel (thereby heeding the warning), this method is called.
**/
- (IBAction)heedDuplicateWarning:(id)sender
{
	// Remove warning panel
	[duplicateWarningPanel orderOut:self];
	[NSApp endSheet:duplicateWarningPanel];
	
	// Update status variable
	isViewingLocalDownloadWarning = NO;
	
	// The user has opted not to download the selected songs
	[tempDownloadList removeAllObjects];
}

/**
 * If the user attempts to download music from their own library we display a warning message to the effect of:
 * This action will result in you having duplicate songs in your iTunes library. Are you sure you want to do this?
 * 
 * If the user clicks download (thereby ignoring the warning), this method is called.
**/
- (IBAction)ignoreDuplicateWarning:(id)sender
{
	// Remove warning panel
	[duplicateWarningPanel orderOut:self];
	[NSApp endSheet:duplicateWarningPanel];
	
	// Update status variable
	isViewingLocalDownloadWarning = NO;
	
	int i;
	for(i = 0; i < [tempDownloadList count]; i++)
	{
		int trackID = [[tempDownloadList objectAtIndex:i] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		[self downloadSong:track];
	}
	
	// Update the download table
	[downloadTable reloadData];
}

- (IBAction)heedDownloadingWarning:(id)sender
{
	// Remove warning panel
	[downloadingWarningPanel orderOut:self];
	[NSApp endSheet:downloadingWarningPanel];
}

- (IBAction)ignoreDownloadingWarning:(id)sender
{
	// Remove warning panel
	[downloadingWarningPanel orderOut:self];
	[NSApp endSheet:downloadingWarningPanel];
	
	// Stop the download
	[self cancelDownload:self];
	
	// Close the window
	[[self window] close];
}

- (IBAction)search:(id)sender
{
	// Set the search string of the tracks controller
	[tracksController setSearchString:[searchField stringValue]];
	
	// Since the songTable changed, the total available probably did too
	[self updateTotalAvailable];
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
		if(isDisplayingSongCount)
		{
			isDisplayingSongCount = NO;
			isDisplayingSongTime  = YES;
			isDisplayingSongSize  = NO;
		}
		else if(isDisplayingSongTime)
		{
			isDisplayingSongCount = NO;
			isDisplayingSongTime  = NO;
			isDisplayingSongSize  = YES;
		}
		else
		{
			isDisplayingSongCount = YES;
			isDisplayingSongTime  = NO;
			isDisplayingSongSize  = NO;
		}
		
		[self updateTotalAvailable];
	}
}

- (IBAction)lcdArtistOrAlbumClicked:(id)sender
{
	ITunesTrack *currentTrack = [player currentTrack];
	
	if(currentTrack == nil) return;
	
	isDisplayingArtist = !isDisplayingArtist;
	
	// Prevent the display of nil or empty strings
	NSString *artist = [currentTrack artist];
	if(artist == nil)
		artist = @"";
	if([artist isEqualToString:@""])
		isDisplayingArtist = NO;
	
	NSString *album = [currentTrack album];
	if(album == nil)
		album = @"";
	if([album isEqualToString:@""])
		isDisplayingArtist = YES;
	
	if(isDisplayingArtist)
	{
		if([player isPlayable])
		{
			[lcdArtistOrAlbumField setStringValue:artist];
		}
		else
		{
			[[lcdArtistOrAlbumField cell] setPlaceholderString:artist];
			[lcdArtistOrAlbumField setStringValue:@""];
		}
	}
	else
	{
		if([player isPlayable])
		{
			[lcdArtistOrAlbumField setStringValue:album];
		}
		else
		{
			[[lcdArtistOrAlbumField cell] setPlaceholderString:album];
			[lcdArtistOrAlbumField setStringValue:@""];
		}
	}
}

- (IBAction)lcdTimeTotalOrLeftClicked:(id)sender
{
	ITunesTrack *currentTrack = [player currentTrack];
	
	if(currentTrack == nil) return;
	
	isDisplayingTotalTime = !isDisplayingTotalTime;
	[[NSUserDefaults standardUserDefaults] setBool:isDisplayingTotalTime forKey:PREFS_TOTAL_TIME];
	
	int totalTime = [currentTrack totalTime];
	
	if(isDisplayingTotalTime)
	{
		NSString *totalTimeStr = [[NSApp delegate] getDurationStr:totalTime longView:YES];
		if([player isPlayable])
		{
			[lcdTimeTotalOrLeftField setStringValue:totalTimeStr];
		}
		else
		{
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:totalTimeStr];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
	}
	else
	{
		int elapsedTime = (int)(totalTime * [player playProgress]);
		
		// We need to get rid of millisecond overlap because we only display seconds
		// Take the following scenario for example:
		// A song is 3000 milliseconds, and 1075 milliseconds have elapsed
		// This brings traditional calculations to 1925 milliseconds left
		// But when we convert these to seconds to display to the user
		// we get 1 second elapsed, and one second left on a 3 second song!  User says huh?
		elapsedTime = elapsedTime - (elapsedTime % 1000);
		
		int timeLeft = totalTime - elapsedTime;
		NSString *timeLeftPreStr = [[NSApp delegate] getDurationStr:timeLeft longView:YES];
		NSString *timeLeftStr = [NSString stringWithFormat:@"-%@", timeLeftPreStr];
		if([player isPlayable])
		{
			[lcdTimeTotalOrLeftField setStringValue:timeLeftStr];
		}
		else
		{
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:timeLeftStr];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
	}
}

- (IBAction)playPauseSong:(id)sender
{
	if([player isPlaying])
	{
		[player pause];
		
		// Update the preview button
		[playPauseButton setImage:[NSImage imageNamed:@"play.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"playPressed.png"]];
		
		// Any time we update the preview button, we should refresh the LCD view as well
		[lcdView setNeedsDisplay:YES];
		
		// We need to change the status icon for the song that was just affected
		// But we don't actually know what row the song is in, and it would be a waste of time to search for it
		[songTable reloadData];
	}
	else
	{
		int selectedRow = [songTable selectedRow];
		if(selectedRow < 0) return;
		
		if(sender == playPauseButton)
		{
			if([player currentTrack] == nil)
			{
				ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:selectedRow];
				
				if([track isVideo])
				{
					[self openMovieInQuickTime:track];
					return;
				}
				else
				{
					[player setTrack:track];
				}
			}
			else
			{
				// The user is just clicking the play button to continue playing an existing song
			}
		}
		else
		{
			// This method was called by double-clicking on a song
			ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:selectedRow];
			
			if([track isVideo])
			{
				[self openMovieInQuickTime:track];
				return;
			}
			else if(track == [player currentTrack])
			{
				// We don't want to reload the track, but we do want to start over from the beginning
				[player setPlayProgress:0];
			}
			else
			{
				// We need to reset the track we're playing
				[player setTrack:track];
			}
		}
		
		[player play];
		
		if([player isPlayingOrBuffering])
		{
			// Update the preview button
			[playPauseButton setImage:[NSImage imageNamed:@"pause.png"]];
			[playPauseButton setAlternateImage:[NSImage imageNamed:@"pausePressed.png"]];
			
			// Any time we update the preview button, we should refresh the LCD view as well
			[lcdView setNeedsDisplay:YES];
			
			// Update just the selected row
			[songTable setNeedsDisplayInRect:[songTable rectOfRow:selectedRow]];
		}
	}
}

- (IBAction)previousSong:(id)sender
{
	// If we're at least 3 seconds into the current song, we simply go back to the beginning
	ITunesTrack *currentTrack = [player currentTrack];
	int elapsedTime = (int)([player playProgress] * [currentTrack totalTime]);
	
	if(elapsedTime >= 3000)
	{
		[player setPlayProgress:0];
		return;
	}
	
	// Get the list of tracks for the playlist we're currently playing in
	// If we're playing something from the current playlist, then the playerTracks variable will be nil
	// Otherwise it will contain the tracks from the proper playlist in the correct order
	NSArray *trackList;
	if(playerTracks)
		trackList = playerTracks;
	else
		trackList = [tracksController arrangedObjects];
	
	// Now we need to find the song in the list
	int i;
	BOOL found = NO;
	for(i = 0; i < [trackList count]; i++)
	{
		ITunesTrack *track = (ITunesTrack *)[trackList objectAtIndex:i];
		
		if([track isEqual:[player currentTrack]])
		{
			// We found the index of the finished track
			found = YES;
			break;
		}
	}
	
	ITunesTrack *previousTrack = nil;
	
	if(found)
	{
		while((--i >= 0) && (previousTrack == nil))
		{
			ITunesTrack *possiblePreviousTrack = [trackList objectAtIndex:i];
			
			if(![possiblePreviousTrack isVideo])
			{
				previousTrack = possiblePreviousTrack;
			}
		}
	}
	
	if(previousTrack)
	{
		// If something is currently playing (or trying to play), then we should continue playing
		// Otherwise, we simply move to the previous song
		
		if([player isPlayingOrBuffering])
		{
			[player setTrack:previousTrack];
			[player play];
		}
		else
		{
			[player setTrack:previousTrack];
		}
	}
	else
	{
		// There was no previous track because we reached the end of the playlist
		[player setTrack:nil];
		
		// Update the preview button
		[playPauseButton setImage:[NSImage imageNamed:@"play.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"playPressed.png"]];
		
		// Any time we update the preview button, we should refresh the LCD view as well
		[lcdView setNeedsDisplay:YES];
	}
	
	// We need to change the status icon for the song that's playing
	// But we don't actually know what row the song is in, and it would be a waste of time to search for it
	[songTable reloadData];
}

- (IBAction)nextSong:(id)sender
{
	// Get the list of tracks for the playlist we're currently playing in
	// If we're playing something from the current playlist, then the playerTracks variable will be nil
	// Otherwise it will contain the tracks from the proper playlist in the correct order
	NSArray *trackList;
	if(playerTracks)
		trackList = playerTracks;
	else
		trackList = [tracksController arrangedObjects];
	
	// Now we need to find the song in the list
	int i;
	BOOL found = NO;
	for(i = 0; i < [trackList count]; i++)
	{
		ITunesTrack *track = (ITunesTrack *)[trackList objectAtIndex:i];
		
		if([track isEqual:[player currentTrack]])
		{
			// We found the index of the finished track
			found = YES;
			break;
		}
	}
	
	ITunesTrack *nextTrack = nil;
	
	if(found)
	{
		while((++i < [trackList count]) && (nextTrack == nil))
		{
			ITunesTrack *possibleNextTrack = [trackList objectAtIndex:i];
			
			if(![possibleNextTrack isVideo])
			{
				nextTrack = possibleNextTrack;
			}
		}
	}
	
	if(nextTrack)
	{
		// If the user manually clicked the next button, the sender will be the button
		// Otherwise, this method was called internally, and the sender is nil
		
		if(sender == nil)
		{
			// This method was called because the last song finished playing
			// Move on to the next song and continue playing
			[player setTrack:nextTrack];
			[player play];
		}
		else
		{
			// The user clicked the play button
			// If something is currently playing (or trying to play), then we should continue playing
			// Otherwise, we simply move to the next song
			
			if([player isPlayingOrBuffering])
			{
				[player setTrack:nextTrack];
				[player play];
			}
			else
			{
				[player setTrack:nextTrack];
			}
		}
	}
	else
	{
		// There was no next track because we reached the end of the playlist
		// If the user manually clicked the next button, the sender will be the button
		// Otherwise, this method was called internally, and the sender is nil
		
		if(sender == nil)
		{
			// We want to leave the track information displaying on the screen
		}
		else
		{
			// The user manually clicked the next button, so we want visual feedback
			// We nil the track so the display reverts to nothing playing
			[player setTrack:nil];
		}
		
		// Update the preview button
		[playPauseButton setImage:[NSImage imageNamed:@"play.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"playPressed.png"]];
		
		// Any time we update the preview button, we should refresh the LCD view as well
		[lcdView setNeedsDisplay:YES];
	}
	
	// We need to change the status icon for the song that's playing
	// But we don't actually know what row the song is in, and it would be a waste of time to search for it
	[songTable reloadData];
}

- (IBAction)stopPreview:(id)sender
{
	[player stop];
	
	// Update the preview button
	[playPauseButton setImage:[NSImage imageNamed:@"play.png"]];
	[playPauseButton setAlternateImage:[NSImage imageNamed:@"playPressed.png"]];
	
	// Any time we update the preview button, we should refresh the LCD view as well
	[lcdView setNeedsDisplay:YES];
	
	// We need to change the status icon for the song that was just affected
	// But we don't actually know what row the song is in, and it would be a waste of time to search for it
	[songTable reloadData];
}

/**
 * Called as the user slides the volume slider.
**/
- (IBAction)changeVolume:(id)sender
{
	float volume = [volumeSliderView floatValue];
	
	[player setVolume:volume];
	[[NSUserDefaults standardUserDefaults] setFloat:volume forKey:PREFS_PLAYER_VOLUME];
}

/**
 * Called when the user clicks the little loud speaker button.
**/
- (IBAction)changeVolumeToMax:(id)sender
{
	[player setVolume:1.0F];
	[volumeSliderView setFloatValue:1.0F];
	[[NSUserDefaults standardUserDefaults] setFloat:1.0F forKey:PREFS_PLAYER_VOLUME];
}

/**
 * Called when the user clicks the little quiet speaker button.
**/
- (IBAction)changeVolumeToMin:(id)sender
{
	[player setVolume:0.0F];
	[volumeSliderView setFloatValue:0.0F];
	[[NSUserDefaults standardUserDefaults] setFloat:0.0F forKey:PREFS_PLAYER_VOLUME];
}

- (void)keyDown:(NSEvent *)event
{
//	DDLogVerbose(@"keyDown: %hu", [event keyCode]);
	
	if([[self window] firstResponder] == songTable)
	{
		// If they hit the Return or Enter keys
		if(([event keyCode] == 36) || ([event keyCode] == 76) || ([event keyCode] == 52))
		{
			[self downloadSelected:self];
		}
		else if([event keyCode] == 49)
		{
			// They hit the spacebar key
			// We want this to be the exact equivalent of clicking the play button
			[self playPauseSong:playPauseButton];
			
			// Switching the icon without a mouseDown/mouseUp event sometimes leaves visual artifacts in the LCD
			[lcdView setNeedsDisplay:YES];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSOutlineView Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * NSOutlienView Delegate method.
 * Called right before the selection changes.
 * We use this to potentially save the view settings of the current playlist.
**/
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	// Save search setting
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	id shadowObject2 = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject2 valueForKey:@"observedObject"];
#else
	NSTreeNode *shadowObject = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject representedObject];
#endif
	
	[selectedPlaylist setSearchString:[searchField stringValue]];
	
	if((playerTracks == nil) && [player isPlayingOrBuffering])
	{
		DDLogVerbose(@"Saving player tracks list...");
		
		playerTracks = [[tracksController arrangedObjects] copy];
		playerPlaylistPersistentID = [[selectedPlaylist persistentID] retain];
		
		DDLogVerbose(@"playerTracks count = %u", [playerTracks count]);
	}

	return true;
}

/**
 * NSOutlineView Delegate method.
 * Called after the selection has changed.
 * We use this method to update the total available text field below the song table.
**/
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	// Get the selected playlist
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	id shadowObject2 = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject2 valueForKey:@"observedObject"];
#else
	NSTreeNode *shadowObject = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject representedObject];
#endif
	
	// Revert to previous search string, if any
	[searchField setStringValue:[selectedPlaylist searchString]];
	[tracksController setSearchString:[selectedPlaylist searchString]];
	
	if([playerPlaylistPersistentID isEqualToString:[selectedPlaylist persistentID]])
	{
		DDLogVerbose(@"Deleting player tracks list...");
		
		[playerTracks release];
		playerTracks = nil;
		
		[playerPlaylistPersistentID release];
		playerPlaylistPersistentID = nil;
	}
	
	// Update the total available text field
	[self updateTotalAvailable];
}

/**
 * NSOutlineView Delegate method.
**/
- (void)outlineView:(NSOutlineView *)outlineView
	willDisplayCell:(id)cell
	 forTableColumn:(NSTableColumn *)column
			   item:(id)item
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
	
	// Set the text color to dark green if the user is subscribed to the playlist
	if([playlist isSubscribed])
	{
		BOOL isRowSelected = [outlineView isRowSelected:[outlineView rowForItem:item]];
		BOOL isFirstResponder = [[[[cell controlView] window] firstResponder] isEqual:[cell controlView]];
		BOOL isKeyWindow = [[[cell controlView] window] isKeyWindow];
		BOOL isApplicationActive = [NSApp isActive];
		
		BOOL isRowHighlighted = (isRowSelected && isFirstResponder && isKeyWindow && isApplicationActive);
		
		NSColor *darkGreen;
		if(isRowHighlighted)
		{
			darkGreen = [NSColor colorWithCalibratedRed:(129.0F / 255.0F)
												  green:(249.0F / 255.0F)
												   blue:( 52.0F / 255.0F) alpha:1.0F];
		}
		else
		{
			darkGreen = [NSColor colorWithCalibratedRed:( 41.0F / 255.0F)
												  green:(103.0F / 255.0F)
												   blue:( 19.0F / 255.0F) alpha:1.0F];
		}
		
		[cell setTextColor:darkGreen];
	}
	else
	{
		[cell setTextColor:[NSColor blackColor]];
	}
	
	
}

/**
 * NSOutlineView Delegate method.
 * Called as an item in the view is being collapsed.
 * If a child, grandchild, etc of the collapsing item is selected, the selection will move to the entire library.
 * This is the default behavior of NSOutlineView.
 * However, in iTunes, the collapsed item becomes selected.  We use this method to obtain that behavior.
**/
- (void)outlineViewItemWillCollapse:(NSNotification *)notification
{
	// Get the actual playlist
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	id shadowObject1 = [[notification userInfo] objectForKey:@"NSObject"];
	ITunesPlaylist *collapsedPlaylist = [shadowObject1 valueForKey:@"observedObject"];
#else
	NSTreeNode *shadowObject1 = [[notification userInfo] objectForKey:@"NSObject"];
	ITunesPlaylist *collapsedPlaylist = [shadowObject1 representedObject];
#endif
	
	// Now get the selected playlist
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
	id shadowObject2 = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject2 valueForKey:@"observedObject"];
#else
	NSTreeNode *shadowObject2 = [sourceTable itemAtRow:[sourceTable selectedRow]];
	ITunesPlaylist *selectedPlaylist = [shadowObject2 representedObject];
#endif
	
	// If the collapsing playlist is a parent, grandparent, etc of the currently selected playlist
	// Then we want to follow iTunes functionality and select the collapsing item
	
	ITunesPlaylist *selectedPlaylistParent = [selectedPlaylist parent];
	
	while(selectedPlaylistParent != nil)
	{
		if(selectedPlaylistParent == collapsedPlaylist)
			[playlistsController setSelectedObjects:[NSArray arrayWithObjects:collapsedPlaylist, nil]];
		
		selectedPlaylistParent = [selectedPlaylistParent parent];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark SongTable Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)songTableWillDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:rowIndex];
	
	BOOL isRowSelected = [songTable isRowSelected:rowIndex];
	BOOL isFirstResponder = [[[[cell controlView] window] firstResponder] isEqual:[cell controlView]];
	BOOL isKeyWindow = [[[cell controlView] window] isKeyWindow];
	BOOL isApplicationActive = [NSApp isActive];
	
	BOOL isRowHighlighted = (isRowSelected && isFirstResponder && isKeyWindow && isApplicationActive);
	
	if([cell isKindOfClass:[NSTextFieldCell class]])
	{
		if([track hasLocalConnection])
		{
			NSColor *grayColor;
			if(isRowHighlighted)
			{
				grayColor = [NSColor colorWithCalibratedRed:(184.0F / 255.0F)
													  green:(175.0F / 255.0F)
													   blue:(184.0F / 255.0F) alpha:1.0F];
			}
			else
			{
				grayColor = [NSColor colorWithCalibratedRed:(134.0F / 255.0F)
													  green:(125.0F / 255.0F)
													   blue:(134.0F / 255.0F) alpha:1.0F];
			}
			
			[cell setTextColor:grayColor];
		}
		else if([track isProtected])
		{
			[cell setTextColor:[NSColor redColor]];
		}
		else
		{
			[cell setTextColor:[NSColor blackColor]];
		}
	}
	
	if(column == column_status)
	{
		// If we're playing something from the current playlist, then the playerTracks variable will be nil
		// Otherwise it will contain the tracks from the proper playlist in the correct order
		
		if((track == [player currentTrack]) && (playerTracks == nil))
		{
			if([player isPlaying])
			{
				if(isRowHighlighted)
					[cell setImage:[NSImage imageNamed:@"whitePlaying.png"]];
				else
					[cell setImage:[NSImage imageNamed:@"playing.png"]];
			}
			else
			{
				if(isRowHighlighted)
					[cell setImage:[NSImage imageNamed:@"whitePaused.png"]];
				else
					[cell setImage:[NSImage imageNamed:@"paused.png"]];
			}
		}
		else
		{
			[cell setImage:nil];
		}
		[cell setStringValue:@""];
	}
	else if(column == column_name)
	{
		if(isRowHighlighted)
		{
			[cell setLeftImage:[NSImage imageNamed:@"downArrowWhite.png"]];
			[cell setAlternateLeftImage:[NSImage imageNamed:@"downArrowAltWhite.png"]];
		}
		else
		{
			[cell setLeftImage:[NSImage imageNamed:@"downArrowGray.png"]];
			[cell setAlternateLeftImage:[NSImage imageNamed:@"downArrowAltGray.png"]];
		}
	}
	else if(column == column_time)
	{
		// Format the time in minutes:seconds from number of milliseconds
		
		[cell setStringValue:[[NSApp delegate] getDurationStr:[track totalTime] longView:YES]];
	}
	else if((column == column_artist) || (column == column_album))
	{
		BOOL showLinks = [[NSUserDefaults standardUserDefaults] boolForKey:PREFS_SHOW_REFERRAL_LINKS];
		
		if(isRowHighlighted && showLinks)
		{
			[cell setRightImage:[NSImage imageNamed:@"rightArrowWhite.png"]];
			[cell setAlternateRightImage:[NSImage imageNamed:@"rightArrowAltWhite.png"]];
		}
		else
		{
			[cell setRightImage:nil];
			[cell setAlternateRightImage:nil];
		}
	}
	else if(column == column_size)
	{
		// Format the size in X.X MB from number of bytes
		
		[cell setStringValue:[[NSApp delegate] getSizeStr:[track fileSize]]];
	}
	else if(column == column_track)
	{
		// Format the track number as X of Y
		// If no track number exists, display the empty string instead of a zero
		
		int trackNumber = [track trackNumber];
		int trackCount = [track trackCount];
		
		if(trackNumber == 0)
		{
			[cell setStringValue:@""];
		}
		else if(trackCount > 0)
		{
			NSString *localizedStr = NSLocalizedString(@"%i of %i", @"iTunes Column Display");
			[cell setStringValue:[NSString stringWithFormat:localizedStr, trackNumber, trackCount]];
		}
	}
	else if(column == column_disc)
	{
		// Format the disc number as X of Y
		// If no disc number exists, display the empty string instead of a zero
		int discNumber = [track discNumber];
		int discCount = [track discCount];
		
		if(discNumber == 0)
		{
			[cell setStringValue:@""];
		}
		else if(discCount > 0)
		{
			NSString *localizedStr = NSLocalizedString(@"%i of %i", @"iTunes Column Display");
			[cell setStringValue:[NSString stringWithFormat:localizedStr, discNumber, discCount]];
		}
	}
	else if(column == column_bitRate)
	{
		// Append the specifier kbps to the bitRate integer
		NSString *localizedStr = NSLocalizedString(@"%i kbps", @"iTunes Column Display");
		[cell setStringValue:[NSString stringWithFormat:localizedStr, [track bitRate]]];
	}
	else if(column == column_dateAdded)
	{
		[cell setStringValue:[shortDF stringFromDate:[track dateAdded]]];
	}
	else if(column == column_year)
	{
		// Display the empty string if no year is given
		ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:rowIndex];
		
		if([track year] == 0)
		{
			[cell setStringValue:@""];
		}
	}
	else if(column == column_rating)
	{
		// Most everything here is handled in DDRatingCell
		// In the future we may want to display in gray those ratings for songs we already have (when row is selected)
	}
}

/**
 * We don't set any tableColumns to be uneditable, so that we can catch double-clicks anywhere in the table.
 * If it's a double-click in the table, we can preview the song that's selected.
**/
- (BOOL)songTableShouldEditTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	// User is double-clicking somewhere in the row of a song
	// Play the song for the user, but obviously don't allow them to edit the read-only data
	
	// Since we're now playing songs from the current playlist, we can get rid of any saved playlist information
	if(playerTracks)
	{
		[playerTracks release];
		playerTracks = nil;
		
		[playerPlaylistPersistentID release];
		playerPlaylistPersistentID = nil;
	}
	
	// Stop any existing song
	[player pause];
	
	// And play the selected song
	[self playPauseSong:self];
	
	return NO;
}

/**
 * This method is called when the user changes his/her selection in the song table.
 * We use this notification to enable/disable the download button.
**/
- (void)songTableViewSelectionDidChange:(NSNotification *)aNotification
{
	int selectedRow = [songTable selectedRow];
	
	[downloadButton setEnabled:(selectedRow >= 0)];
}

/**
 * This method is called to see if a particular row (or set of rows) is allowed to be dragged.
**/
- (BOOL)songTableWriteRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	// Todo...
	return NO;
}

/**
 * This method is called by our custom RHTypeSelectTableView class.
 * In this case, we've only configured one column to contain a clickable button, so we know the column will be
 * the name column, and the button is the download button.
**/
- (void)songTableDidClickButton:(int)buttonIndex atTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	// Get the track the user clicked
	ITunesTrack *track = [[tracksController arrangedObjects] objectAtIndex:rowIndex];
	
	if(column == column_name)
	{
		// User clicked on the download button of a specific track
		// Add the track to the download list
		// This will also handle updating the track download status
		[self downloadSong:track];
		
		// Note: the above method does not handle updating any GUI elements
		// Thus we still need to update the tables
		
		// If we call [songTable reloadData] we would update all visible rows
		// So instead we are going to tell the songTable to only update the row of the updated track
		[songTable setNeedsDisplayInRect:[songTable rectOfRow:rowIndex]];
		
		// Update the download table
		[downloadTable reloadData];
	}
	else if((column == column_artist) || (column == column_album))
	{
		int referralLinkMode = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_REFERRAL_LINK_MODE];
		
		NSString *base;
		NSString *account;
		NSString *camp;
		NSString *creative;
		
		if(referralLinkMode == PREFS_REFERRAL_UK)
		{
			base     = @"http://www.amazon.co.uk";
			account  = @"deusty-21";
			camp     = @"1634";
			creative = @"6738";
		}
		else if(referralLinkMode == PREFS_REFERRAL_CA)
		{
			base     = @"http://www.amazon.ca";
			account  = @"deusty-20";
			camp     = @"15121";
			creative = @"330641";
		}
		else if(referralLinkMode == PREFS_REFERRAL_DE)
		{
			base     = @"http://www.amazon.de";
			account  = @"deusty0d-21";
			camp     = @"1638";
			creative = @"6742";
		}
		else
		{
			base     = @"http://www.amazon.com";
			account  = @"robbhans-20";
			camp     = @"1789";
			creative = @"9325";
		}
		
		NSString *keywords;
		if(column == column_artist)
			keywords = [NSURL urlEncodeValue:[NSString stringWithFormat:@"%@", [track artist]]];
		else
			keywords = [NSURL urlEncodeValue:[NSString stringWithFormat:@"%@ %@", [track artist], [track album]]];
		
		NSString *link = @"%@/gp/search?ie=UTF8&keywords=%@&tag=%@&index=music&linkCode=ur2&camp=%@&creative=%@";
		
		NSString *fullLink = [NSString stringWithFormat:link, base, keywords, account, camp, creative];
		
		// We want to open the URL in the background
		NSArray* urls = [NSArray arrayWithObject:[NSURL URLWithString:fullLink]];
		
		[[NSWorkspace sharedWorkspace] openURLs:urls
						withAppBundleIdentifier:nil
										options:NSWorkspaceLaunchWithoutActivation
				 additionalEventParamDescriptor:nil
							  launchIdentifiers:nil];
	}
}

/**
 * Implement this method if the table uses bindings for data.
 * Use something like
 *   return [[[arrayController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
 * Could also use it to supply string representations for non-string data, or to search only part of visible text.
**/
- (NSString *)typeSelectTableView:(id)tv stringValueForTableColumn:(NSTableColumn *)column row:(int)row
{
	// Only return proper information for columns that use standard strings (Same as iTunes)
	if(column == column_name)
		return [[[tracksController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
	if(column == column_kind)
		return [[[tracksController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
	if(column == column_album)
		return [[[tracksController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
	if(column == column_genre)
		return [[[tracksController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
	if(column == column_artist)
		return [[[tracksController arrangedObjects] objectAtIndex:row] valueForKey:[column identifier]];
	
	return @"";
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DownloadTable Datasource and Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Standard datasource method.
**/
- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [downloadList count];
}

/**
 * Standard datasource method.
 * Note that our status column is configured as an NSImageCell, so we need to return NSImage objects.
**/
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	int trackID = [[downloadList objectAtIndex:rowIndex] intValue];
	ITunesTrack *track = [data iTunesTrackForID:trackID];
	
	if([[column identifier] isEqualToString:@"status"])
	{
		if([track downloadStatus] == DOWNLOAD_STATUS_QUEUED)
		{
			return [NSImage imageNamed:@"DownloadQueued.png"];
		}
		else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADING)
		{
			return [NSImage imageNamed:@"Downloading.png"];
		}
		else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADED)
		{
			return [NSImage imageNamed:@"DownloadComplete.png"];
		}
		else
		{
			return [NSImage imageNamed:@"DownloadFailed.png"];
		}
	}
	else if([[column identifier] isEqualToString:@"file"])
	{
		NSString *name = [track name];
		NSString *artist = [track artist];
		
		if(artist)
			return [NSString stringWithFormat:@"%@ - %@", name, artist];
		else
			return name;
	}
	else
	{
		// Because NSCell's are shared between multiple rows, we MUST set the doubleValue of the cell
		// in the downloadTableView:willDisplayCell::: method below.
		// So we don't bother with it here.
		
		return [NSNumber numberWithDouble:0.0];
	}
}

- (void)downloadTableWillDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	if([[column identifier] isEqualToString:@"progress"])
	{
		int trackID = [[downloadList objectAtIndex:rowIndex] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
		
		if([track downloadStatus] == DOWNLOAD_STATUS_QUEUED)
		{
			[cell setImage1:[NSImage imageNamed:@"downloadStop.png"]];
			[cell setAlternateImage1:[NSImage imageNamed:@"downloadAltStop.png"]];
			
			[cell setImage2:nil];
			[cell setAlternateImage2:nil];
			
			NSString *localizedStr = NSLocalizedString(@"Remove from queue", @"Download table status");
			[cell setStringValue:localizedStr];
			
			[cell setDoubleValue:0.0];
		}
		else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADING)
		{
			[cell setImage1:[NSImage imageNamed:@"downloadStop.png"]];
			[cell setAlternateImage1:[NSImage imageNamed:@"downloadAltStop.png"]];
			
			[cell setImage2:nil];
			[cell setAlternateImage2:nil];
			
			NSString *localizedStr = NSLocalizedString(@"Downloading...", @"Download table status");
			[cell setStringValue:localizedStr];
			
			[cell setDoubleValue:([httpClient progress] * 100.0)];
		}
		else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADED)
		{
			[cell setImage1:[NSImage imageNamed:@"downloadPlay.png"]];
			[cell setAlternateImage1:[NSImage imageNamed:@"downloadAltPlay.png"]];
			
			[cell setImage2:nil];
			[cell setAlternateImage2:nil];
			
			NSString *localizedStr = NSLocalizedString(@"Download Complete", @"Download table status");
			[cell setStringValue:localizedStr];
			
			[cell setDoubleValue:0.0];
		}
		else
		{
			[cell setImage1:[NSImage imageNamed:@"downloadResume.png"]];
			[cell setAlternateImage1:[NSImage imageNamed:@"downloadAltResume.png"]];
			
			[cell setImage2:[NSImage imageNamed:@"downloadStop.png"]];
			[cell setAlternateImage2:[NSImage imageNamed:@"downloadAltStop.png"]];
			
			NSString *localizedStr = NSLocalizedString(@"Download Failed", @"Download table status");
			[cell setStringValue:localizedStr];
			
			[cell setDoubleValue:0.0];
		}
	}
}

- (BOOL)downloadTableShouldEditTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	return NO;
}

/**
 * This method is called to see if a particular row (or set of rows) is allowed to be dragged.
**/
- (BOOL)downloadTableWriteRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	// Note: We only allow one item at a time to be dragged right now.
	// We will probably change this in the future...
	
	int trackID = [[downloadList objectAtIndex:[rowIndexes firstIndex]] intValue];
	ITunesTrack *track = [data iTunesTrackForID:trackID];
	
	if([track downloadStatus] == DOWNLOAD_STATUS_QUEUED)
	{
		// Copy the row numbers to the pasteboard.
		NSData *pbData = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
		[pboard declareTypes:[NSArray arrayWithObject:MyPrivateTableViewDataType] owner:self];
		[pboard setData:pbData forType:MyPrivateTableViewDataType];
		
		// Return YES to allow the drag to begin
		return YES;
	}
	
	// Return NO to prevent the drag from beginning
	return NO;
}

/**
 * This method is called to validate a proposed drop location.
 * The drop is not being made yet, this is just to update the GUI during the drag process.
**/
- (NSDragOperation)downloadTableValidateDrop:(id<NSDraggingInfo>)info
								 proposedRow:(int)row
					   proposedDropOperation:(NSTableViewDropOperation)op
{
	if(row < [downloadList count])
	{
		int trackID = [[downloadList objectAtIndex:row] intValue];
		ITunesTrack *track = [data iTunesTrackForID:trackID];
	
		if([track downloadStatus] == DOWNLOAD_STATUS_QUEUED)
		{
			[downloadTable setDropRow:row dropOperation:NSTableViewDropAbove];
			return NSDragOperationMove;
		}
		else
		{
			return NSDragOperationNone;
		}
	}
	else
	{
		// Trying to move to the very end of the list
		[downloadTable setDropRow:row dropOperation:NSTableViewDropAbove];
		return NSDragOperationMove;
	}
}

- (BOOL)downloadTableAcceptDrop:(id<NSDraggingInfo>)info
							row:(int)row
				  dropOperation:(NSTableViewDropOperation)operation
{
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:MyPrivateTableViewDataType];
    NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    int dragRow = [rowIndexes firstIndex];
	
	ITunesTrack *track = nil;
	if(row < [downloadList count])
	{
		int trackID = [[downloadList objectAtIndex:row] intValue];
		track = [data iTunesTrackForID:trackID];
	}
	
	if((track == nil) || ([track downloadStatus] == DOWNLOAD_STATUS_QUEUED))
	{
		// Move the specified row to its new location...
		
		if(dragRow <= row)
		{
			BOOL isSelected = [downloadTable selectedRow] == dragRow;
			
			id dragObject = [downloadList objectAtIndex:dragRow];
			[downloadList insertObject:dragObject atIndex:row];
			[downloadList removeObjectAtIndex:dragRow];
			
			if(isSelected) [downloadTable selectRow:(row-1) byExtendingSelection:NO];
			[downloadTable reloadData];
			return YES;
		}
		else
		{
			BOOL isSelected = [downloadTable selectedRow] == dragRow;
			
			id dragObject = [downloadList objectAtIndex:dragRow];
			[downloadList insertObject:dragObject atIndex:row];
			[downloadList removeObjectAtIndex:dragRow+1];
			
			if(isSelected) [downloadTable selectRow:row byExtendingSelection:NO];
			[downloadTable reloadData];
			return YES;
		}
	}
	
	return NO;
}

- (void)downloadTableDidClickButton:(int)buttonIndex atTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	int trackID = [[downloadList objectAtIndex:rowIndex] intValue];
	ITunesTrack *track = [data iTunesTrackForID:trackID];
	
	BOOL cancelDownload  = NO;
	BOOL removeDownload  = NO;
	BOOL requeueDownload = NO;
	BOOL playSong        = NO;
	
	if([track downloadStatus] == DOWNLOAD_STATUS_QUEUED)
	{
		removeDownload = YES;
	}
	else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADING)
	{
		cancelDownload = YES;
	}
	else if([track downloadStatus] == DOWNLOAD_STATUS_DOWNLOADED)
	{
		playSong = YES;
	}
	else if([track downloadStatus] == DOWNLOAD_STATUS_FAILED)
	{
		removeDownload = YES;
		
		if(buttonIndex == 0)
		{
			requeueDownload = YES;
		}
	}
	
	DDLogVerbose(@"cancelDownload  : %d", cancelDownload);
	DDLogVerbose(@"removeDownload  : %d", removeDownload);
	DDLogVerbose(@"requeueDownload : %d", requeueDownload);
	DDLogVerbose(@"playSong        : %d", playSong);
	
	if(cancelDownload)
	{
		[track setDownloadStatus:DOWNLOAD_STATUS_FAILED];
		[self cancelDownload:self];
		
		[downloadTable setNeedsDisplayInRect:[downloadTable rectOfRow:rowIndex]];
		
		// Increment downloadIndex
		downloadIndex++;
		
		// Move on to the next song in the list if possible
		if(downloadIndex < [downloadList count])
		{
			// There are more songs to download
			[self downloadNextSong];
		}
		else
		{
			// Update status
			status = STATUS_READY;
			
			// Remove the black dot from the close button
			[[self window] setDocumentEdited:NO];
		}
	}
	if(removeDownload)
	{
		[track setDownloadStatus:DOWNLOAD_STATUS_NONE];
		[downloadList removeObjectAtIndex:rowIndex];
		
		// Since we decreased the size of our downloadList, we may need to decrease our downloadIndex as well
		if(downloadIndex >= rowIndex)
		{
			downloadIndex--;
		}
		
		[downloadTable reloadData];
	}
	if(requeueDownload)
	{
		[self downloadSong:track];
		[downloadTable reloadData];
	}
	if(playSong)
	{
		NSString *scriptName = @"playSong";
		NSString *scriptPath = [[NSBundle mainBundle] pathForResource:scriptName ofType:@"applescript"];
		
		NSString *trackName   = [track name]   ? [track name]   : @"";
		NSString *trackArtist = [track artist] ? [track artist] : @"";
		NSString *trackAlbum  = [track album]  ? [track album]  : @"";
		
		NSString *originalSource = [self stringWithContentsOfFile:scriptPath];
		NSString *source = [NSString stringWithFormat:originalSource, trackName, trackArtist, trackAlbum];
		
		NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
		NSString *result = [[ascript executeAndReturnError:nil] stringValue];
		
		DDLogInfo(@"Applescript result: %@", result);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSTableView Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)column
			  row:(int)rowIndex
{
	if(tableView == songTable)
		[self songTableWillDisplayCell:cell forTableColumn:column row:rowIndex];
	else
		[self downloadTableWillDisplayCell:cell forTableColumn:column row:rowIndex];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(int)rowIndex
{
	if(tableView == songTable)
		return [self songTableShouldEditTableColumn:column row:rowIndex];
	else
		return [self downloadTableShouldEditTableColumn:column row:rowIndex];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([aNotification object] == songTable)
		[self songTableViewSelectionDidChange:aNotification];
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
                                                    toPasteboard:(NSPasteboard*)pboard
{
	if(tableView == songTable)
		return [self songTableWriteRowsWithIndexes:rowIndexes toPasteboard:pboard];
	else
		return [self downloadTableWriteRowsWithIndexes:rowIndexes toPasteboard:pboard];
}

- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info
                                                      proposedRow:(int)row
                                            proposedDropOperation:(NSTableViewDropOperation)op
{
	if(tableView == songTable)
		return NSDragOperationNone;
	else
		return [self downloadTableValidateDrop:info proposedRow:row proposedDropOperation:op];
}

- (BOOL)tableView:(NSTableView *)tableView
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(int)row
	dropOperation:(NSTableViewDropOperation)op
{
	if(tableView == songTable)
		return NO;
	else
		return [self downloadTableAcceptDrop:info row:row dropOperation:op];
}

/**
 * Invoked by DDTableView when a button within a DDButtonCell is clicked
**/
- (void)tableView:(NSTableView *)tableView
   didClickButton:(int)buttonIndex
	atTableColumn:(NSTableColumn *)column
			  row:(int)rowIndex
{
	DDLogInfo(@"tableView:didClickButton:%i atTableColumn:row:%i", buttonIndex, rowIndex);
	
	if(tableView == songTable)
		[self songTableDidClickButton:buttonIndex atTableColumn:column row:rowIndex];
	else
		[self downloadTableDidClickButton:buttonIndex atTableColumn:column row:rowIndex];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSSplitView Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * If the delegate implements this method, it is invoked after the NSSplitView is resized.
 * The size of the NSSplitView before the user resized it is indicated by oldSize;
 * the subviews should be resized such that the sum of the sizes of the subviews plus the sum of the thickness of
 * the dividers equals the size of the NSSplitView’s new frame. You can get the thickness of a divider through the
 * dividerThickness method.
 *
 * Note that if you implement this delegate method to resize subviews on your own,
 * the NSSplitView does not perform any error checking for you.
 * However, you can invoke adjustSubviews to perform the default sizing behavior.
**/
- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	if(sender == splitView1)
	{
		// Keep the splitView1LeftSubview the same width whenever the window is resized.
		// Only the splitView1RightSubview should grow and shrink.
		// The only restriction on this rule is that the splitView1RightSubview must be at least 300 pixels wide.
		
		NSSize oldRightSize = [splitView1RightSubview frame].size;
		NSSize newSize = [sender frame].size;
		
		CGFloat widthDiff = newSize.width - oldSize.width;
		CGFloat newRightWidth = oldRightSize.width + widthDiff;
		
		if(newRightWidth < 300) newRightWidth = 300;
		
		CGFloat newLeftWidth = newSize.width - [splitView1 dividerThickness] - newRightWidth;
		
		[splitView1LeftSubview setFrameSize:NSMakeSize(newLeftWidth, newSize.height)];
		
		CGFloat oldRightY = [splitView1RightSubview frame].origin.y;
		CGFloat newRightX = newLeftWidth + [splitView1 dividerThickness];
		[splitView1RightSubview setFrame:NSMakeRect(newRightX, oldRightY, newRightWidth, newSize.height)];
	}
	else
	{
		// Keep the splitView2BottomSubview the same height whenever the window is resized.
		// Only the splitView2TopSubview should grow and shrink.
		// The only restriction on this rule is that the splitView2TopSubview must be at least 150 pixels high.
		
		NSSize oldTopSize = [splitView2TopSubview frame].size;
		NSSize newSize = [sender frame].size;
		
		CGFloat heightDiff = newSize.height - oldSize.height;
		CGFloat newTopHeight = oldTopSize.height + heightDiff;
		
		if(newTopHeight < 150) newTopHeight = 150;
		
		[splitView2TopSubview setFrameSize:NSMakeSize(newSize.width, newTopHeight)];
		
		CGFloat newBottomHeight = newSize.height - [splitView2 dividerThickness] - newTopHeight;
		
		CGFloat oldBottomX = [splitView2BottomSubview frame].origin.x;
		CGFloat newBottomY = newTopHeight + [splitView2 dividerThickness];
		[splitView2BottomSubview setFrame:NSMakeRect(oldBottomX, newBottomY, newSize.width, newBottomHeight)];
	}
}


/**
 * Allows the delegate to constrain the
 * minimum coordinate limit of a divider when the user drags it.
**/
- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	if(sender == splitView1)
	{
		return 150;
	}
	else
	{
		return 150;
	}
}

/**
 * Allows the delegate to constrain the
 * maximum coordinate limit of a divider when the user drags it.
**/
- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	if(sender == splitView1)
	{
		return ([splitView1 frame].size.width - [splitView1 dividerThickness] - 300);
	}
	else
	{
		return ([splitView2 frame].size.height - [splitView2 dividerThickness] - 50);
	}
}

/**
 * We implement this method to prevent the scrollview resize rect
 * from invading the source table vertical scrollbar.
**/
- (NSRect)splitView:(NSSplitView *)splitView
	  effectiveRect:(NSRect)proposedEffectiveRect
	   forDrawnRect:(NSRect)drawnRect
   ofDividerAtIndex:(NSInteger)dividerIndex
{
	if(splitView == splitView1)
	{
		NSScrollView *scrollView = (NSScrollView *)[[sourceTable superview] superview];
		
		NSSize contentSize = [scrollView contentSize];
		NSSize documentSize = [[scrollView documentView] frame].size;
		
		BOOL isVerticalScrollbarVisible = [scrollView hasVerticalScroller] && documentSize.height > contentSize.height;
		
		if(isVerticalScrollbarVisible)
		{
			NSRect moveRect = drawnRect;
			moveRect.size.width += 3;
			
			return moveRect;
		}
		else
		{
			NSRect moveRect = drawnRect;
			moveRect.origin.x -= 3;
			moveRect.size.width += 6;
			
			return moveRect;
		}
	}
	else
	{
		return proposedEffectiveRect;
	}
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	if(sender == splitView2)
	{
		if(subview == splitView2BottomSubview)
		{
			return YES;
		}
	}
	return NO;
}

- (BOOL)splitView:(NSSplitView *)sender shouldCollapseSubview:(NSView *)subview
                               forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
	if(sender == splitView2)
	{
		if(subview == splitView2BottomSubview)
		{
			return YES;
		}
	}
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ITunesForeignInfo Delegate Methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method is called by ITunesForeignInfo when it has discovered
 * matching tracks in the foreign and local iTunes library.
 * We use this delegate method to immediately update the table view, if it's displaying the given track.
 * 
 * Note: This method is run in a background thread.
**/
- (void)iTunesForeignInfo:(ITunesForeignInfo *)data didFindConnectionForITunesTrack:(ITunesTrack *)track
{
	// Updating the table row directly from the background thread is dangerous
	// and has caused several application crashes that I've witnessed.
	// For this purpose we perform the delicate operation on the main thread only.
	[self performSelectorOnMainThread:@selector(updateSongTableRowWithTrack:)
						   withObject:track
						waitUntilDone:YES];
}

/**
 * This method is meant to be run on the main thread only.
 * Note that we don't force a reload of the entire table view.  We only update the proper row.
**/
- (void)updateSongTableRowWithTrack:(ITunesTrack *)track
{
	// Get the tracks
	NSArray *tracks = [tracksController arrangedObjects];
	
	// If the track is visible in the table, tell the tableView to reload that row
	NSRange visibleRows = [songTable rowsInRect:[songTable visibleRect]];
	
	uint row;
	for(row = visibleRows.location; row < visibleRows.location + visibleRows.length; row++)
	{
		ITunesTrack *currentTrack = [tracks objectAtIndex:row];
		
		if([currentTrack isEqual:track])
		{
			[songTable setNeedsDisplayInRect:[songTable rectOfRow:row]];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ITunesPlayer Delegate Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Called if a song was unable to immediately start playing.
**/
- (void)iTunesPlayerDidChangeTrack:(id)sender
{
	// Update the LCD display
	ITunesTrack *currentTrack = [player currentTrack];
	
	// Check for nil track
	if(currentTrack == nil)
	{
		[[lcdSongField cell] setPlaceholderString:@""];
		[lcdSongField setStringValue:@""];
		
		NSString *nothingPlayingStr = NSLocalizedString(@"Nothing Playing", @"LCD Placeholder");
		
		[[lcdArtistOrAlbumField cell] setPlaceholderString:nothingPlayingStr];
		[lcdArtistOrAlbumField setStringValue:@""];
		
		[lcdTimeElapsedField setStringValue:@""];
		[[lcdTimeElapsedField cell] setPlaceholderString:@"0:00"];
		
		[[lcdTimeTotalOrLeftField cell] setPlaceholderString:@"0:00"];
		[lcdTimeTotalOrLeftField setStringValue:@""];
	}
	else
	{
		[[lcdSongField cell] setPlaceholderString:[currentTrack name]];
		[lcdSongField setStringValue:@""];
		
		// Prevent the display of nil or empty strings
		NSString *artist = [currentTrack artist];
		if(artist == nil)
			artist = @"";
		if([artist isEqualToString:@""])
			isDisplayingArtist = NO;
		
		NSString *album = [currentTrack album];
		if(album == nil)
			album = @"";
		if([album isEqualToString:@""])
			isDisplayingArtist = YES;
		
		if(isDisplayingArtist)
		{
			[[lcdArtistOrAlbumField cell] setPlaceholderString:artist];
			[lcdArtistOrAlbumField setStringValue:@""];
		}
		else
		{
			[[lcdArtistOrAlbumField cell] setPlaceholderString:album];
			[lcdArtistOrAlbumField setStringValue:@""];
		}
		
		// We may be restarting the song after it was paused halfway through, so don't hardcode anything
		int totalTime = [currentTrack totalTime];
		int elapsedTime = (int)(totalTime * [player playProgress]);
		
		// We need to get rid of millisecond overlap because we only display seconds
		// Take the following scenario for example:
		// A song is 3000 milliseconds, and 1075 milliseconds have elapsed
		// This brings traditional calculations to 1925 milliseconds left
		// But when we convert these to seconds to display to the user
		// we get 1 second elapsed, and one second left on a 3 second song!  User says huh?
		elapsedTime = elapsedTime - (elapsedTime % 1000);
		
		NSString *elapsedTimeStr = [[NSApp delegate] getDurationStr:elapsedTime longView:YES];
		[lcdTimeElapsedField setStringValue:@""];
		[[lcdTimeElapsedField cell] setPlaceholderString:elapsedTimeStr];
		
		if(isDisplayingTotalTime)
		{
			NSString *totalTimeStr = [[NSApp delegate] getDurationStr:totalTime longView:YES];
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:totalTimeStr];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
		else
		{
			int timeLeft = totalTime - elapsedTime;
			NSString *timeLeftStr = [[NSApp delegate] getDurationStr:timeLeft longView:YES];
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:[NSString stringWithFormat:@"-%@", timeLeftStr]];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
	}
	
	[lcdSongProgressView setNeedsDisplay:YES];
	[lcdView setNeedsDisplay:YES];
}

- (void)iTunesPlayerDidStartLoading:(id)sender
{
	[stopPreviewButton setHidden:NO];
}

/**
 * Songs may not start playing right away, as they may have to first load part of the network stream.
 * This delegate method is called when the song has actually started playing.
**/
- (void)iTunesPlayerDidStartPlaying:(id)sender
{
	// Update the LCD display
	ITunesTrack *currentTrack = [player currentTrack];
	
	[lcdSongField setStringValue:[currentTrack name]];
	
	// Prevent the display of nil or empty strings
	NSString *artist = [currentTrack artist];
	if(artist == nil)
		artist = @"";
	if([artist isEqualToString:@""])
		isDisplayingArtist = NO;
	
	NSString *album = [currentTrack album];
	if(album == nil)
		album = @"";
	if([album isEqualToString:@""])
		isDisplayingArtist = YES;
	
	if(isDisplayingArtist)
		[lcdArtistOrAlbumField setStringValue:artist];
	else
		[lcdArtistOrAlbumField setStringValue:album];
	
	// We may be restarting the song after it was paused halfway through, so don't hardcode anything
	int totalTime = [currentTrack totalTime];
	int elapsedTime = (int)(totalTime * [player playProgress]);
	
	// We need to get rid of millisecond overlap because we only display seconds
	// Take the following scenario for example:
	// A song is 3000 milliseconds, and 1075 milliseconds have elapsed
	// This brings traditional calculations to 1925 milliseconds left
	// But when we convert these to seconds to display to the user
	// we get 1 second elapsed, and one second left on a 3 second song!  User says huh?
	elapsedTime = elapsedTime - (elapsedTime % 1000);
	
	NSString *elapsedTimeStr = [[NSApp delegate] getDurationStr:elapsedTime longView:YES];
	[lcdTimeElapsedField setStringValue:elapsedTimeStr];
	
	if(isDisplayingTotalTime)
	{
		NSString *totalTimeStr = [[NSApp delegate] getDurationStr:totalTime longView:YES];
		[lcdTimeTotalOrLeftField setStringValue:totalTimeStr];
	}
	else
	{
		int timeLeft = totalTime - elapsedTime;
		NSString *timeLeftStr = [[NSApp delegate] getDurationStr:timeLeft longView:YES];
		[lcdTimeTotalOrLeftField setStringValue:[NSString stringWithFormat:@"-%@", timeLeftStr]];
	}
	
	[lcdSongProgressView setNeedsDisplay:YES];
	[lcdView setNeedsDisplay:YES];
	
	// We need to change the status icon for the song that's playing
	// But we don't actually know what row the song is in, and it would be a waste of time to search for it
	[songTable reloadData];
}

- (void)iTunesPlayerDidChangeLoadOrTime:(id)sender
{
	ITunesTrack *currentTrack = [player currentTrack];
	
	int totalTime = [currentTrack totalTime];
	int elapsedTime = (int)(totalTime * [player playProgress]);
	
	// We need to get rid of millisecond overlap because we only display seconds
	// Take the following scenario for example:
	// A song is 3000 milliseconds, and 1075 milliseconds have elapsed
	// This brings traditional calculations to 1925 milliseconds left
	// But when we convert these to seconds to display to the user
	// we get 1 second elapsed, and one second left on a 3 second song!  User says huh?
	elapsedTime = elapsedTime - (elapsedTime % 1000);
	
	NSString *elapsedTimeStr = [[NSApp delegate] getDurationStr:elapsedTime longView:YES];
	if([player isPlayable])
	{
		[lcdTimeElapsedField setStringValue:elapsedTimeStr];
	}
	else
	{
		[[lcdTimeElapsedField cell] setPlaceholderString:elapsedTimeStr];
		[lcdTimeElapsedField setStringValue:@""];
	}
	
	if(isDisplayingTotalTime)
	{
		NSString *totalTimeStr = [[NSApp delegate] getDurationStr:totalTime longView:YES];
		if([player isPlayable])
		{
			[lcdTimeTotalOrLeftField setStringValue:totalTimeStr];
		}
		else
		{
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:totalTimeStr];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
	}
	else
	{
		int timeLeft = totalTime - elapsedTime;
		NSString *timeLeftStr = [[NSApp delegate] getDurationStr:timeLeft longView:YES];
		if([player isPlayable])
		{
			[lcdTimeTotalOrLeftField setStringValue:[NSString stringWithFormat:@"-%@", timeLeftStr]];
		}
		else
		{
			[[lcdTimeTotalOrLeftField cell] setPlaceholderString:[NSString stringWithFormat:@"-%@", timeLeftStr]];
			[lcdTimeTotalOrLeftField setStringValue:@""];
		}
	}
	
	[lcdSongProgressView setNeedsDisplay:YES];
	[lcdView setNeedsDisplay:YES];
}

- (void)iTunesPlayerDidFinishLoading:(id)sender
{
	[stopPreviewButton setHidden:YES];
}

- (void)iTunesPlayerDidFinishPlaying:(id)sender
{
	[self nextSong:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utility Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method updates the totalAvailable information to reflect the current table view.
**/
- (void)updateTotalAvailable
{
	int index = 0;
	int numSongs = 0;
	uint64_t totalTime = 0;
	uint64_t totalSize = 0;
	
	// Loop through every song in the table
	NSArray *tracks = [tracksController arrangedObjects];
	
	for(index = 0; index < [tracks count]; index++)
	{
		ITunesTrack *track = [tracks objectAtIndex:index];
		
		numSongs++;
		totalTime += [track totalTime];
		totalSize += [track fileSize];
	}
	
	if(numSongs == 0)
	{
		[totalAvailableField setStringValue:@""];
	}
	else
	{
		if(isDisplayingSongCount)
		{
			NSString *count = [[NSApp delegate] getCountStr:numSongs];
			[totalAvailableField setStringValue:count];
		}
		else if(isDisplayingSongTime)
		{
			NSString *duration = [[NSApp delegate] getDurationStr:totalTime longView:NO];
			[totalAvailableField setStringValue:duration];
		}
		else
		{
			NSString *size = [[NSApp delegate] getSizeStr:totalSize];
			[totalAvailableField setStringValue:size];
		}
	}
}

/**
 * Creates (if necessary) and returns the temporary directory for the given iTunes libarary.
 * 
 * This directory will be created inside the application's temporary directory. (See appTempDir method)
**/
- (NSString *)libTempDir
{
	NSString *appTempDir = [[NSApp delegate] applicationTemporaryDirectory];
	NSString *libTempDir = [appTempDir stringByAppendingPathComponent:[self libraryID]];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	if([[NSFileManager defaultManager] fileExistsAtPath:libTempDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:libTempDir attributes:nil];
	}
	
	return libTempDir;
}

/**
 * Creates (if necessary) and returns the directory that songs should be moved into after downloading.
 * This directory will be inside the iTunes Music directory, and somewhere within a subfolder called Mojo Downloads.
 * This ensures that if iTunes is configured to copy songs into the iTunes library,
 * there will not be duplicate copies of songs floating around the user's hard drive.
**/
- (NSString *)libPermDir
{
	ITunesData *localData = [ITunesData allLocalITunesData];
	
	NSString *musicDir = [[NSURL URLWithString:[localData musicFolder]] relativePath];
	NSString *mojoDir = [musicDir stringByAppendingPathComponent:@"Mojo Downloads"];
	NSString *libPermDir = [mojoDir stringByAppendingPathComponent:[self libraryID]];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	if([[NSFileManager defaultManager] fileExistsAtPath:mojoDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:mojoDir attributes:nil];
	}
	if([[NSFileManager defaultManager] fileExistsAtPath:libPermDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:libPermDir attributes:nil];
	}
	
	return libPermDir;
}

/**
 * Creates (if necessary) and returns the backup directory that songs should be moved into after downloading.
 * This is only used if an error occurs while attempting to move the file into the libPermDir.
**/
- (NSString *)libPermBackupDir
{
	NSString *musicDir = [@"~/Music" stringByExpandingTildeInPath];
	NSString *mojoDir = [musicDir stringByAppendingPathComponent:@"Mojo Downloads"];
	NSString *backupDir = [mojoDir stringByAppendingPathComponent:[self libraryID]];
	
	// We have to make sure the directory exists, because NSURLDownload won't create it for us
	// And simply fails to save the download to disc if a directory in the path doesn't exist
	if([[NSFileManager defaultManager] fileExistsAtPath:mojoDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:mojoDir attributes:nil];
	}
	if([[NSFileManager defaultManager] fileExistsAtPath:backupDir] == NO)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:backupDir attributes:nil];
	}
	
	return backupDir;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark AppleScript Methods:
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)stringWithContentsOfFile:(NSString *)filePath
{
	NSError *error = nil;
	NSString *result = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
	
	if (result == nil)
	{
		DDLogError(@"Error reading file \"%@\" : %@", [filePath lastPathComponent], error);
	}
	
	return result;
}

/**
 * This method handles adding a song (with the given path) to the iTunes library.
 * This method will automatically add it to the corrent playlist based on user preferences as well.
**/
- (void)addSongWithPath:(NSString *)songPath
{
	// Create AppleScript source
	NSString *source;
	
	int playlistOption = [[NSUserDefaults standardUserDefaults] integerForKey:PREFS_PLAYLIST_OPTION];
	if(playlistOption == PLAYLIST_OPTION_NONE)
	{
		NSString *scriptName = @"addSongToLibrary";
		NSString *scriptPath = [[NSBundle mainBundle] pathForResource:scriptName ofType:@"applescript"];
		
		NSString *originalSource = [self stringWithContentsOfFile:scriptPath];
		
		// 1 argument: song path
		source = [NSString stringWithFormat:originalSource, songPath];
	}
	else if(playlistOption == PLAYLIST_OPTION_FOLDER)
	{
		NSString *scriptName = @"addSongToPlaylistInMojoFolder";
		NSString *scriptPath = [[NSBundle mainBundle] pathForResource:scriptName ofType:@"applescript"];
		
		NSString *originalSource = [self stringWithContentsOfFile:scriptPath];
		
		NSString *playlistName;
		if(bonjourResource)
			playlistName = [bonjourResource displayName];
		else if(xmppUserResource)
			playlistName = [xmppUserResource mojoDisplayName];
		else
			playlistName = [BonjourUtilities shareNameForTXTRecordData:remoteData];
		
		// 2 arguments: song path, and playlist name
		source = [NSString stringWithFormat:originalSource, songPath, playlistName];
	}
	else
	{
		NSString *scriptName = @"addSongToPlaylist";
		NSString *scriptPath = [[NSBundle mainBundle] pathForResource:scriptName ofType:@"applescript"];
		
		NSString *originalSource = [self stringWithContentsOfFile:scriptPath];
		
		// 2 arguments: song path, and playlist name
		NSString *playlistName = [[NSUserDefaults standardUserDefaults] stringForKey:PREFS_PLAYLIST_NAME];
		if((playlistName == nil) || [playlistName isEqualToString:@""]) {
			playlistName = @"Mojo";
		}
		source = [NSString stringWithFormat:originalSource, songPath, playlistName];
	}
	
	DDLogVerbose(@"Executing applescript...");
	
	// Create AppleScript from modified source, and execute it
	NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
	NSString *result = [[ascript executeAndReturnError:nil] stringValue];
	[ascript release];
	
	DDLogInfo(@"Applescript result: %@", result);
}

- (void)openMovieInQuickTime:(ITunesTrack *)track
{
	// Create URL from track
	int trackID = [track trackID];
	
	NSString *persistentTrackID = [track persistentID];
	NSString *filename = [[track location] lastPathComponent];
	
	NSString *relativePath = [NSString stringWithFormat:@"%i/%@/%@", trackID, persistentTrackID, filename];
	NSURL *movieURL = [NSURL URLWithString:relativePath relativeToURL:baseURL];
	
	// Create AppleScript source
	NSString *source;
	
	NSString *scriptName = @"openInQuickTime";
	NSString *scriptPath = [[NSBundle mainBundle] pathForResource:scriptName ofType:@"applescript"];
	
	NSString *originalSource = [self stringWithContentsOfFile:scriptPath];
	
	// 1 argument: song path
	source = [NSString stringWithFormat:originalSource, [movieURL absoluteString]];
	
	// Create AppleScript from modified source, and execute it
	NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
	[ascript executeAndReturnError:nil];
	[ascript release];
}

@end
