#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>

@class BonjourResource;
@class XMPPUserAndMojoResource;
@class SocketConnector;
@class ITunesForeignInfo;
@class LibrarySubscriptions;
@class ITunesPlayer;
@class HTTPClient;


@interface MSWController : NSWindowController
{
	// Stored Bonjour resource (if browsing local service)
	BonjourResource *bonjourResource;
	
	// Stored XMPP user and resource (if browsing remote service)
	XMPPUserAndMojoResource *xmppUserResource;
	
	// Stored NSData from remote service's txtRecordData (if browsing direct connection)
	NSData *remoteData;
	
	// Current status of the window
	// This is used to aid in cancelling actions
	int status;
	
	// Variables used for downloading files from a mojo server
	SocketConnector *socketConnector;
	UInt16 gatewayPort;
	NSURL *baseURL;
	HTTPClient *httpClient;
	
	// Variables pertaining to iTunes Data
	ITunesForeignInfo *data;
	
	// Variables pertaining to iTunes Player
	ITunesPlayer *player;
	NSArray *playerTracks;
	NSString *playerPlaylistPersistentID;
	
	// Variables pertaining to downloading songs
	NSMutableArray *downloadList;
	int downloadIndex;
	int downloadTotalSize;
	int downloadCurrentSize;
	
	// Variables pertaining to formatting iTunes Data for display
	NSDateFormatter *shortDF;
	
	// For switching between various views
	BOOL isDisplayingArtist;
	BOOL isDisplayingTotalTime;
	BOOL isDisplayingSongCount;
	BOOL isDisplayingSongTime;
	BOOL isDisplayingSongSize;
	
	// For displaying warning to users downloading songs from their own library
	BOOL hasSeenLocalDownloadWarning;
	BOOL isViewingLocalDownloadWarning;
	NSMutableArray *tempDownloadList;
	
	// Interface Builder outlets
    IBOutlet id column_album;
    IBOutlet id column_artist;
    IBOutlet id column_bitRate;
    IBOutlet id column_bpm;
	IBOutlet id column_comments;
    IBOutlet id column_composer;
    IBOutlet id column_dateAdded;
    IBOutlet id column_disc;
    IBOutlet id column_genre;
    IBOutlet id column_kind;
    IBOutlet id column_name;
    IBOutlet id column_playCount;
    IBOutlet id column_rating;
    IBOutlet id column_size;
    IBOutlet id column_status;
    IBOutlet id column_time;
    IBOutlet id column_track;
    IBOutlet id column_year;
    IBOutlet id downloadButton;
    IBOutlet id downloadingWarningPanel;
    IBOutlet id downloadTable;
    IBOutlet id duplicateWarningPanel;
    IBOutlet id lcdArtistOrAlbumField;
    IBOutlet id lcdSongField;
    IBOutlet id lcdSongProgressView;
    IBOutlet id lcdTimeElapsedField;
    IBOutlet id lcdTimeTotalOrLeftField;
    IBOutlet id lcdView;
    IBOutlet id panel1;
    IBOutlet id panel1authenticationView;
    IBOutlet id panel1contentView;
    IBOutlet id panel1passwordField;
    IBOutlet id panel1passwordImage;
    IBOutlet id panel1progress;
    IBOutlet id panel1progressView;
    IBOutlet id panel1savePasswordButton;
    IBOutlet id panel1text;
	IBOutlet id panel1helpButton;
    IBOutlet id panel1tryAgainButton;
    IBOutlet id panel2;
    IBOutlet id panel2passwordField;
    IBOutlet id panel2passwordImage;
    IBOutlet id panel2savePasswordButton;
    IBOutlet id panel2text;
    IBOutlet id playlistsController;
    IBOutlet id playPauseButton;
    IBOutlet id searchField;
    IBOutlet id songTable;
    IBOutlet id sourceTable;
    IBOutlet id splitView1;
	IBOutlet id splitView1LeftSubview;
	IBOutlet id splitView1RightSubview;
    IBOutlet id splitView2;
	IBOutlet id splitView2TopSubview;
	IBOutlet id splitView2BottomSubview;
	IBOutlet id stopPreviewButton;
    IBOutlet id totalAvailableField;
    IBOutlet id tracksController;
    IBOutlet id volumeSliderView;
}
- (id)initWithLocalResource:(BonjourResource *)resource;
- (id)initWithRemoteResource:(XMPPUserAndMojoResource *)userResource;
- (id)initWithRemoteURL:(NSURL *)remoteURL;

- (BOOL)isLocalResource;
- (BOOL)isRemoteResource;
- (NSString *)libraryID;

- (IBAction)addRemoveColumn:(id)sender;
- (IBAction)cancelDownload:(id)sender;
- (IBAction)cancelLoad:(id)sender;
- (IBAction)changeVolume:(id)sender;
- (IBAction)changeVolumeToMax:(id)sender;
- (IBAction)changeVolumeToMin:(id)sender;
- (IBAction)downloadSelected:(id)sender;
- (IBAction)heedDownloadingWarning:(id)sender;
- (IBAction)heedDuplicateWarning:(id)sender;
- (IBAction)ignoreDownloadingWarning:(id)sender;
- (IBAction)ignoreDuplicateWarning:(id)sender;
- (IBAction)lcdArtistOrAlbumClicked:(id)sender;
- (IBAction)lcdTimeTotalOrLeftClicked:(id)sender;
- (IBAction)nextSong:(id)sender;
- (IBAction)passwordEnteredForDownload:(id)sender;
- (IBAction)passwordEnteredForLoad:(id)sender;
- (IBAction)previousSong:(id)sender;
- (IBAction)playPauseSong:(id)sender;
- (IBAction)search:(id)sender;
- (IBAction)stopPreview:(id)sender;
- (IBAction)totalAvailableClicked:(id)sender;
- (IBAction)helpLoad:(id)sender;
- (IBAction)tryAgainLoad:(id)sender;
@end
