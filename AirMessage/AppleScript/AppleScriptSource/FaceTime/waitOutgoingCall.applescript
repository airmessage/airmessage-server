--Monitors an active outgoing call, and returns when / whether the user accepted or rejected the call
set labelsCancel to {"Cancel", "Annuler", "キャンセル"}
set labelsEnd to {"End", "Raccrocher", "終了"}

tell application "System Events"
	tell process "FaceTime"
		repeat
			set buttonName to name of button 2 of window 1
			--The label is "cancel" if the user rejected the call
			if labelsCancel contains buttonName then
				return false
			else if labelsEnd does not contain buttonName then
				return true
			end if
			
			delay 0.1
		end repeat
	end tell
end tell
