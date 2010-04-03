-- This script adds a song to 2 separate playlists in iTunes
-- The first playlist is just a normal playlist, and may be standalone, or within any folder playlist
-- The second playlist must be within the Mojo folder
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
-- This script expects 3 arguments
-- Argument 1:
--    The full POSIX path to the song
--    Ex: "/Users/robbie/Music/iTunes/Mojo/quack.mp3"
-- Argument 2:
--    The name of the first playlist we will be adding the song to
--    If a playlist with the given name doesn't exist, it is created
-- Argument 3:
--    The name of the second playlist we will be adding the song to
--    This playlist is assumed to be in the Mojo folder
--    If the Mojo folder doesn't exist, it is created
--    If a playlist with the given name doesn't exist in the Mojo folder, it is created


-- Get the songPath (argument 1), and convert the UNIX path to an HFS path
set mySongPath to "%@"
set mySongFile to (POSIX file mySongPath)

-- Get the primary playlist name (argument 2)
set myPlaylistName1 to "%@"

-- Get the secondary playlist name (argument 3)
set myPlaylistName2 to "%@"

tell application "iTunes"
	
	-- Find the correct playlist (playlist 1)
	set myPlaylistName to myPlaylistName1
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
	
	-- Add the song to the iTunes library, and into the primary playlist
	set addedTrack to add mySongFile to myPlaylist
	
	-- Find the Mojo folder playlist
	if exists folder playlist named "Mojo" then
		set folderRef to folder playlist named "Mojo"
	else
		set folderRef to (make new folder playlist with properties {name:"Mojo"})
	end if
	
	-- Find the correct playlist (playlist 2) within the Mojo folder playlist
	set myPlaylistName to myPlaylistName2
	set foundPlaylist to false
	set allPlaylists to user playlists
	repeat with i from 1 to (number of items in allPlaylists)
		set currentPlaylist to (item i of allPlaylists)
		if name of currentPlaylist is myPlaylistName then
			if smart of currentPlaylist is false then
				if exists parent of currentPlaylist then
					if parent of currentPlaylist is folderRef then
						set foundPlaylist to true
						set myPlaylist to currentPlaylist
					end if
				end if
			end if
		end if
	end repeat
	if not foundPlaylist then
		set myPlaylist to (make new playlist with properties {name:myPlaylistName})
		move myPlaylist to folderRef
	end if
	
	-- Duplicate the song into the secondary playlist
	duplicate addedTrack to myPlaylist
	
	-- Return the track ID
	set addedTrackID to id of addedTrack
	return addedTrackID
	
end tell