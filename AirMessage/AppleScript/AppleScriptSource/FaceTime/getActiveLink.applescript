--Creates and returns a FaceTime link for the current call

--Open FaceTime
tell application "FaceTime" to activate

--Wait for FaceTime to initialize
tell application "System Events"
	tell process "FaceTime"
		set windowReady to false
		repeat while not windowReady
			if exists window 1
				set windowReady to true
				exit repeat
			end if
			
			delay 0.1
		end repeat
	end tell
end tell

tell application "System Events"
	tell process "FaceTime"
		--Open sidebar
		repeat with buttonEl in buttons of window 1
			if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl = "toggleSidebarButton") then
				click buttonEl
			end if
		end repeat
		
		--Minimize window
		keystroke "m" using command down
		
		set originalClipboard to the clipboard

		--Click "share link" button
		set linkButton to button 2 of last group of list 1 of list 1 of scroll area 2 of window 1
		click linkButton
		delay 0.1
		click menu item 1 of menu of linkButton
		
		repeat
			if the clipboard is not originalClipboard
				return the clipboard
			end if
		end repeat
	end tell
end tell
