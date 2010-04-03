-- This script removes all the songs from a given playlist in iTunes
-- This script is not meant to be run directly, but rather to be run from within Cocoa
-- 
-- Originally, this script used command line arguments to set the playlist name
-- However, this would fail if any of the arguments contained special characters.
-- 
-- The script is now designed to be run from within Cocoa, using code similar to this:
-- NSString *originalSource = [NSString stringWithContentsOfFile:scriptPath];
-- NSString *source = [NSString stringWithFormat:originalSource, argument1];
-- NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
-- [ascript executeAndReturnError:nil];
-- 
-- From this point forward, strings to be replaced, will be referred to as arguments
-- 
-- This script expects 1 arguments
-- Argument 1:
--    The name of the playlist to remove tracks from


-- Get the playlist name (argument 1)
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
	
	-- Now remove all the tracks from the playlist (if we found it)
	if foundPlaylist then
		delete tracks in myPlaylist
	end if
	
end tell