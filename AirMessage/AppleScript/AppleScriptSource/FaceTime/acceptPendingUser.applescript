--Accepts the first user waiting for access to the call

tell application "System Events"
	tell process "FaceTime"
		repeat with groupEl in groups of list 1 of list 1 of scroll area 2 of window 1
			try
				if (exists attribute "AXIdentifier" of groupEl) and (value of attribute "AXIdentifier" of groupEl = "InCallControlsPendingParticipantCell") then
					repeat while exists button 2 of groupEl
						--Accept the user
						click button 2 of groupEl
					end repeat
					return true
				end if
			end try
		end repeat
		
		return false
	end tell
end tell
