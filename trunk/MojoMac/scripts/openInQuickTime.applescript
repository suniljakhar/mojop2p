-- This script opens a URL in QuickTime
-- This script is not meant to be run directly, but rather to be run from within Cocoa
-- 
-- This script expects 1 argument
-- Argument 1:
--    The URL to open (as an absolute path in the form of a string)
--    Ex: "http://10.0.1.4:12345/30415/7481DFFA/Superbad.mp4"

tell application "QuickTime Player"
	
	set players to (open location "%@")
	
	activate
	
	repeat with player in players
		tell player
			set auto play to true
			play
		end tell
	end repeat
	
end tell
