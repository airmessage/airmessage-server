--Leaves a call in progress, or cancels a pending outgoing call
set labelsCancel to {"Cancel", "Annuler", "キャンセル"}
set labelsEnd to {"End", "Raccrocher", "終了"}

tell application "System Events"
	tell process "FaceTime"
		--If we're in a call, target the button with an AXIdentifier of "leaveButton"
		repeat with buttonEl in buttons of window 1
			if (exists attribute "AXIdentifier" of buttonEl) and (value of attribute "AXIdentifier" of buttonEl = "leaveButton") then
				click buttonEl
				return
			end if
		end repeat
		
		--If we're trying to make an outgoing call, target the "cancel" or "end" button
		set targetButton to button 2 of window 1
		set buttonName to name of targetButton
		
		--The label is "cancel" if the user rejected the call
		if labelsCancel contains buttonName then
			click targetButton
			return
		--The label is "end" if we're waiting for a pending outgoing call
		else if labelsEnd contains buttonName then
			click targetButton
			return
		end if
	end tell
end tell
