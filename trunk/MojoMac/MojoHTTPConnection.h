#import "HTTPConnection.h"

/**
 * The HTTP Server does mostly what we want it to do except for one major thing.
 * We really don't want to send requests over the network for straight files, because it poses a security risk.
 * For example, someone could send a simple HTTP GET command for /Users/robbie/Documents/DeepDarkSecrets.txt
 * If the HTTP server just served up any file that was requested, this would actually work.
 * What we could do, to get around this problem, would be to make sure the requested file is in the iTunes library.
 * But this would require looping through every song in the library, and performing a string compare until we find it.
 * While this isn't overly slow, especially when you compare it to the network bottleneck, there is another problem.
 * File paths change. So if the user slightly changes the song name, track number, album, artist name, etc...
 * the file path will change.
 * A better solution is to send the persistent track ID. Then we can lookup the current path in the iTune library.
 * There's one small annoyance about this solution too. We can't directly lookup the track from the persistent track ID.
 * We need the track ID to directly lookup the track.
 * So the final solution is to pass both the track ID and the persistent track ID of the song we want.
 * We can use both to get the file path for the correct song, and 99.9% of the time the lookup can be done in 1 step.
**/
@interface MojoHTTPConnection : HTTPConnection
{
	BOOL isMojoConnection;
}

/**
 * This methood indicates whether the connection is a mojo connection.
 * There are mojo, and non-mojo connections.
 * A mojo connection represents a connection from a MojoClient object.
 * An example of a non-mojo connection would be streaming of a song URL to a QTMovie object.
**/
- (BOOL)isMojoConnection;

- (void)abandonSocketAndDie;

@end
