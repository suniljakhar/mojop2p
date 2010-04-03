-- This script adds a song to the iTunes library, and directly to a specified playlist
-- This script is not meant to be run directly, but rather to be run from within Cocoa
-- 
-- Originally, this script used command line arguments to set the path to the song
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
-- This script expects 2 arguments
-- Argument 1:
--    The full POSIX path to the song
--    Ex: "/Users/robbie/Music/Mojo/song.mp3"
-- Argument 2:
--    The name of the playlist we will be adding the song to
--    If a playlist with the given name doesn't exist, it is created


-- Get the songPath (argument 1), and convert the UNIX path to an HFS path
set mySongPath to "%@"
set mySongFile to (POSIX file mySongPath)

-- Get the playlist name (argument 2)
set myPlaylistName to "%@"

tell application "iTunes"
	
	-- First we need to find the correct playlist
	set foundPlaylist to false
	set allPlaylists to user playlists
	repeat with i from 1 to (number of items in allPlaylists)
		set currentPlaylist to (item i of allPlaylists)
		if name of currentPlaylist is myPlaylistName then
			if smart of currentPlaylist is false then
				set foundPlaylist to true
				set myPlaylist to currentPlaylist
			end if
		end if
	end repeat
	if not foundPlaylist then
		set myPlaylist to (make new playlist with properties {name:myPlaylistName})
	end if
	
	-- Now we need to add the song to myPlaylist
	set addedTrack to add mySongFile to myPlaylist
	
	-- Return the track ID
	set addedTrackID to id of addedTrack
	return addedTrackID
	
end tell