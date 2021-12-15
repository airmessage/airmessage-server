--Centers the FaceTime window in the middle of the screen

on main(moveX, moveY)
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
		end tell
	end tell

	--Open FaceTime
	tell application "FaceTime" to activate
	
	--Center the window
	tell application "System Events"
		tell process "FaceTime"
			set {windowWidth, windowHeight} to size of window 1
			set position of window 1 to {moveX - (windowWidth / 2), moveY - (windowHeight / 2)}
		end tell
	end tell
end main
