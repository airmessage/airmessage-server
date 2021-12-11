--Creates a new FaceTime link and returns it
tell application "System Events"
	tell process "FaceTime"
		activate
		
		set linkButton to button 1 of window 1
		click linkButton
		delay 0.1
		click menu item 1 of menu of linkButton
		delay 0.5
		return the clipboard
	end tell
end tell
