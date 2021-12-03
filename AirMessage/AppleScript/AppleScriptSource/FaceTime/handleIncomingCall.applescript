--Accepts or rejects a pending incoming call
on main(accept)
	tell application "System Events"
		--Make sure the notification exists
		if not (exists group 1 of UI element 1 of scroll area 1 of window 1 of application process "NotificationCenter") then
			return false
		end if
		
		--Get the first notification
		set notificationGroup to group 1 of UI element 1 of scroll area 1 of window 1 of application process "NotificationCenter"
		
		--Handle the call
		if accept then
			set buttonAccept to button 1 of notificationGroup
			click buttonAccept
		else
			set buttonReject to button 1 of notificationGroup
			click buttonReject
		end if
		
		return true
	end tell
end main
