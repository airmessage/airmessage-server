tell application "System Events"
	tell process "FaceTime"
		repeat with buttonEl in buttons of window 1
			if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl = "leaveButton") then
				click buttonEl
			end if
		end repeat
	end tell
end tell
