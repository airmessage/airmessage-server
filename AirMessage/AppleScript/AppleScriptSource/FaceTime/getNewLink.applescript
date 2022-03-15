--Creates a new FaceTime link and returns it

--Open FaceTime
tell application "FaceTime" to activate

--Wait for FaceTime to initialize
tell application "System Events"
	tell process "FaceTime"
		set windowReady to false
		
		repeat while not windowReady
			if exists window 1 then
				repeat with buttonEl in buttons of window 1
					if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl contains "NS") then
						set windowReady to true
						exit repeat
					end if
				end repeat
			end if
			
			delay 0.1
		end repeat
		
		delay 0.2
	end tell
end tell

tell application "System Events"
	tell process "FaceTime"
		--Clear the clipboard
		set the clipboard to ""
		
		--Click "Create Link" button
		set linkButton to button 1 of window 1
		click linkButton
		delay 0.1
		click menu item 1 of menu of linkButton
		
		repeat
			if the clipboard is not ""
				return the clipboard as string
			end if
			delay 0.1
		end repeat
	end tell
end tell
