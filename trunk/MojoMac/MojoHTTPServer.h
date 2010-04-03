#import "HTTPServer.h"

// A notification with this name is posted after the bonjour service is published
// The NSNetService that was published is passed as the object of the notification
#define DidPublishServiceNotification  @"DidPublishService"


@interface MojoHTTPServer : HTTPServer

+ (MojoHTTPServer *)sharedInstance;

- (void)setITunesLibraryID:(NSString *)libID numberOfSongs:(int)numSongs;
- (void)updateShareName;
- (void)updateRequiresPassword;
- (void)updateRequiresTLS;

- (int)numberOfMojoConnections;

- (void)addConnection:(id)newSocket;

@end
