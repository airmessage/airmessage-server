on main(addressList)
	set labelsMessages to {"Messages", "メッセージ"}
	
	--Open FaceTime
	tell application "FaceTime" to activate
	
	--Wait for FaceTime to initialize
	tell application "System Events"
		tell process "FaceTime"
			set windowReady to false
			repeat while not windowReady
				if exists window 1 then
					repeat with buttonEl in buttons of window 1
						try
							if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl contains "NS") then
								set windowReady to true
								exit repeat
							end if
						end try
					end repeat
				end if
				delay 0.1
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
			
			--Wait for the request to go through
			repeat
				if (exists of radio group 1 of createSheet) and (enabled of radio group 1 of createSheet) then
					--Click the create button and join the call
					set buttonCreate to radio button 1 of radio group 1 of createSheet
					
					# FaceTime button will disable while it queries contacts, so wait for it to enable again, then click it until the sheet disappears
					repeat while exists createSheet
						if enabled of buttonCreate then
							click buttonCreate
						end if
						delay 0.1
					end repeat
					
					return true
				else if exists button 2 of createSheet then
					set buttonName to name of button 2 of createSheet
					repeat with label in labelsMessages
						if buttonName contains label then
							--Invite with Messages
							--Dismiss the sheet
							click button 1 of createSheet
							
							return false
						end if
					end repeat
				end if
				
				delay 0.1
			end repeat
		end tell
	end tell
end main
