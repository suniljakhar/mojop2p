-- This script adds a song to the iTunes library
-- This script is not meant to be run directly, but rather to be run from within Cocoa
-- 
-- Originally, this script used command line parameters to set the path to the song
-- IE - the user would execute the script and pass the argument(s) like this:
-- $ osascript scriptName.scpt "/Users/robbie/Music/Mojo/song.mp3"
-- However, this would fail if any of the arguments contained special characters, eg:
-- $ osascript scriptName.scpt "/Users/robbie/Music/Beyoncé/song.mp3"
-- It seems that the special characters didn't make it past the shell
-- 
-- The script is now designed to be run from within Cocoa, using code similar to this:
-- NSString *originalSource = [NSString stringWithContentsOfFile:scriptPath];
-- NSString *source = [NSString stringWithFormat:originalSource, argument1, argument2, ...];
-- NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
-- [ascript executeAndReturnError:nil];
-- 
-- From this point forward, strings to be replaced, will be referred to as arguments
-- 
-- This script expects 1 argument
-- Argument 1:
--    The full POSIX path to the song
--    Ex: "/Users/robbie/Music/Mojo/song.mp3"


-- Get the songPath (argument 1), and convert the UNIX path to an HFS path
set mySongPath to "%@"
set mySongFile to (POSIX file mySongPath)

tell application "iTunes"
	
	-- Add the song to the iTunes library
	set addedTrack to add mySongFile
	
	-- Return the track ID
	set addedTrackID to id of addedTrack
	return addedTrackID
	
end tell