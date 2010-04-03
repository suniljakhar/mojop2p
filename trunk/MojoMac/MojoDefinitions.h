
// MOJO SERVICE DEFINITIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MOJO_SERVICE_TYPE          @"_maestro._tcp."

#define DEFAULT_XMPP_SERVER        @"deusty.com"
#define DEFAULT_XMPP_VHOST         @"deusty.com"

#define TXTRCD_VERSION             @"txtvers"
#define TXTRCD_ZLIB_SUPPORT        @"zlib"
#define TXTRCD_GZIP_SUPPORT        @"gzip"
#define TXTRCD_REQUIRES_PASSWORD   @"passwd"
#define TXTRCD_REQUIRES_TLS        @"tls"

#define TXTRCD_STUNT_VERSION       @"stunt"
#define TXTRCD_STUN_VERSION        @"stun"
#define TXTRCD_SEARCH_VERSION      @"search"

#define TXTRCD1_LIBRARY_ID         @"Library Persistent ID"
#define TXTRCD1_SHARE_NAME         @"Share Name"
#define TXTRCD1_NUM_SONGS          @"Number of Songs"

#define TXTRCD2_LIBRARY_ID         @"LibraryPersistentID"
#define TXTRCD2_SHARE_NAME         @"ShareName"
#define TXTRCD2_NUM_SONGS          @"NumberOfSongs"

// INTER-APPLICATION NOTIFICATIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HelperReadyDistributedNotification  @"Ready"

#define DidFindLocalServiceNotification     @"DidFindLocalService"
#define DidUpdateLocalServiceNotification   @"DidUpdateLocalService"
#define DidRemoveLocalServiceNotification   @"DidRemoveLocalService"

#define DidUpdateRosterNotification         @"DidUpdateRoster"
/*
#define DidFindRemoteServiceNotification    @"DidFindRemoteServie"
#define DidUpdateRemoteServiceNotification  @"DidUpdateRemoteService"
#define DidRemoveRemoteServiceNotification  @"DidRemoveRemoteService"
*/
#define XMPPClientConnectingNotification    @"XMPPClientConnecting"
#define XMPPClientDidConnectNotification    @"XMPPClientDidConnect"
#define XMPPClientDidDisconnectNotification @"XMPPClientDidDisconnect"

#define XMPPClientAuthFailureNotification   @"XMPPClientAuthFailure"

#define XMPPClientDidGoOnlineNotification   @"XMPPClientDidGoOnline"

// MOJO PREFERENCES
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define PREFS_SEEN_WELCOME               @"Seen Welcome 2"
#define PREFS_INSTALL_DATE               @"Install Date"

#define PREFS_SUBSCRIPTIONS              @"Subscriptions"
#define PREFS_LIBRARY_ID                 @"Library ID"
#define PREFS_SERVICE_NAME               @"Service Name"
#define PREFS_SHARE_NAME                 @"Share Name"
#define PREFS_DISPLAY_NAME               @"Display Name"
#define PREFS_REQUIRE_PASSWORD           @"Require Password"
#define PREFS_REQUIRE_TLS                @"Require TLS"
#define PREFS_LAST_SYNC                  @"Last Syncronization"
#define PREFS_IS_UPDATING                @"Is Updating"

#define SUBSCRIPTION_INDEX               @"Playlist Index"
#define SUBSCRIPTION_MYNAME              @"My Playlist Name"

#define PREFS_BACKGROUND_HELPER_ENABLED  @"EnableMenuItem"
#define PREFS_LAUNCH_AT_LOGIN            @"LaunchAtLogin"
#define PREFS_DISPLAY_MENU_ITEM          @"DisplayMenuItem"

#define PREFS_UPDATE_INTERVAL            @"Subscriptions Update Interval"

#define PREFS_XMPP_AUTOLOGIN             @"XMPP Auto Login"
#define PREFS_XMPP_USERNAME              @"XMPP Username"
#define PREFS_XMPP_SERVER                @"XMPP Server"
#define PREFS_XMPP_PORT                  @"XMPP Port"
#define PREFS_XMPP_USESSL                @"XMPP Use SSL"
#define PREFS_XMPP_ALLOWSELFSIGNED       @"XMPP Allow SSL SelfSigned"
#define PREFS_XMPP_ALLOWSSLMISMATCH      @"XMPP Allow SSL HostName Mismatch"
#define PREFS_XMPP_RESOURCE              @"XMPP Resource"

#define PREFS_ITUNES_LOCATION            @"iTunes Location"

#define PREFS_PLAYLIST_OPTION            @"iTunes Playlist Option"
#define PREFS_PLAYLIST_NAME              @"iTunes Playlist Name"

#define PLAYLIST_OPTION_NONE             0
#define PLAYLIST_OPTION_FOLDER           1
#define PLAYLIST_OPTION_SINGLE           2

#define PREFS_SHARE_FILTER               @"Share Filter"
#define PREFS_SHARED_PLAYLISTS           @"Shared Playlists"

#define PREFS_SERVER_PORT_NUMBER         @"Server Port Number"
#define PREFS_SHOW_REFERRAL_LINKS        @"Show Referral Links"
#define PREFS_REFERRAL_LINK_MODE         @"Referral Link Mode"
#define PREFS_DEMO_MODE                  @"Demo Mode"
#define PREFS_STUNT_FEEDBACK             @"STUNT Feedback"

#define PREFS_REFERRAL_US                0
#define PREFS_REFERRAL_UK                1
#define PREFS_REFERRAL_CA                2
#define PREFS_REFERRAL_DE                3

#define PREFS_RECENT_URLS                @"Recent URLs"

#define PREFS_DISPLAY_NAMES              @"Display Names"

#define PREFS_PLAYER_VOLUME              @"Player Volume"
#define PREFS_TOTAL_TIME                 @"Display Total Time"

// STATUS DEFINITIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STATUS_READY                 0
#define STATUS_INFO_CONNECTING      10
#define STATUS_INFO_DOWNLOADING     11
#define STATUS_XML_RESOLVING        20
#define STATUS_XML_CONNECTING       21
#define STATUS_XML_AUTHENTICATING   22
#define STATUS_XML_DOWNLOADING      23
#define STATUS_XML_PARSING          24
#define STATUS_SONG_RESOLVING       30
#define STATUS_SONG_CONNECTING      31
#define STATUS_SONG_AUTHENTICATING  32
#define STATUS_SONG_DOWNLOADING     33
#define STATUS_FINISHING           100
#define STATUS_ERROR               200
#define STATUS_QUITTING            300

// MOJO URL'S
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MOJO_URL_MAIN          @"http://www.deusty.com/software/"
#define MOJO_URL_HELP          @"http://www.deusty.com/support/mojo_faq.php"
#define MOJO_URL_FORUM         @"http://www.deusty.com/forum/"
#define MOJO_URL_SCREENCASTS   @"http://www.deusty.com/screencasts/"
#define MOJO_URL_TROUBLESHOOT  @"http://www.deusty.com/software/mac_troubleshoot.php"
#define MOJO_URL_STUNT_INFO    @"http://www.deusty.com/stunt/index.php"
#define MOJO_URL_ACCOUNT_GUIDE @"http://www.deusty.com/support/accountGuide.php"

// MISCELLANEOUS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STUNT_UUID   @"STUNT UUID"
