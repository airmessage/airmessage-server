on main(addressList)
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
	
	tell application "System Events"
		tell process "FaceTime"
			--Click the "New FaceTime" button
			set createButton to button 2 of window 1
			click createButton
			
			--Get the sheet
			set createSheet to sheet 1 of window 1
			
			--Focus the input field
			set inputField to text field 1 of createSheet
			set focused of inputField to true
			
			--Enter the addresses
			repeat with address in addressList
				keystroke address
				keystroke return
			end repeat
			
			if exists of radio group 1 of createSheet then
				--Click the create button and join the call
				delay 0.3
				set buttonCreate to radio button 1 of radio group 1 of createSheet
				click buttonCreate
				
				return true
			else
				--Dismiss the sheet
				click button 1 of createSheet
				
				return false
			end if
		end tell
	end tell
end main
