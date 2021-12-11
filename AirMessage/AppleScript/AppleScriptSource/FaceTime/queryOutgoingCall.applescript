--Given an active outgoing call, returns when / whether the user accepted or rejected the call
set labelsCancel to {"Cancel", "Annuler", "キャンセル"}
set labelsEnd to {"End", "Raccrocher", "終了"}

tell application "System Events"
	tell process "FaceTime"
		set targetButton to button 2 of window 1
		set buttonName to name of targetButton
		--The label is "cancel" if the user rejected the call
		if labelsCancel contains buttonName then
			click targetButton --Exit out of the call
			return "rejected"
		else if labelsEnd does not contain buttonName then
			return "accepted"
		else
			return "pending"
		end if
	end tell
end tell
