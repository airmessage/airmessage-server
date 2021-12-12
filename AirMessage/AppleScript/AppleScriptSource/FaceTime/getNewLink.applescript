--Creates a new FaceTime link and returns it

--Open FaceTime
tell application "FaceTime" to activate

--Wait for FaceTime to initialize
tell application "System Events"
	tell process "FaceTime"
		set windowReady to false
		repeat while not windowReady
			repeat with buttonEl in buttons of window 1
				if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl contains "NS") then
					set windowReady to true
					exit repeat
				end if
			end repeat
		end repeat
	end tell
end tell

--Get the FaceTime link
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
