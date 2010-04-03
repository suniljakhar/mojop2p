-- This script plays a song in iTunes
-- This script is not meant to be run directly, but rather to be run from within Cocoa
-- 
-- The script is designed to be run from within Cocoa, using code similar to this:
-- NSString *originalSource = [NSString stringWithContentsOfFile:scriptPath];
-- NSString *source = [NSString stringWithFormat:originalSource, argument1, argument2, ...];
-- NSAppleScript *ascript = [[NSAppleScript alloc] initWithSource:source];
-- [ascript executeAndReturnError:nil];
-- 
-- From this point forward, strings to be replaced, will be referred to as arguments
-- 
-- This script expects 3 arguments
-- Argument 1:
--    The song name
--    Ex: "Hells Bells"
-- Argument 2:
--    The song artist
--    Ex: "AC-DC"
-- Argument 3:
--    The song album
--    Ex: "Back In Black"

tell application "iTunes"
	
	set songName to "%@"
	set songArtist to "%@"
	set songAlbum to "%@"
	
	set songSearch to songName & " " & songArtist & " " & songAlbum
	
	set musicPlaylist to some playlist whose special kind is Music
	
	set songList to search musicPlaylist for songSearch
	set song to item 1 of songList
	play song
	
end tell