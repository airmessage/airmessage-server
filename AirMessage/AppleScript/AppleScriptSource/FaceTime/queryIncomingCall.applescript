--Checks Notification Center for incoming calls, and returns the caller's name
tell application "System Events"
	--Wait for a notification call to appear
	if not (exists group 1 of UI element 1 of scroll area 1 of window 1 of application process "NotificationCenter") then
		return ""
	end if
	
	--Get the first notification
	set notificationGroup to group 1 of UI element 1 of scroll area 1 of window 1 of application process "NotificationCenter"
	
	--Make sure we're dealing with a FaceTime call notification
	if (exists static text 1 of notificationGroup) and (value of static text 1 of notificationGroup contains "FaceTime Video") then
		--Return the name of the caller
		set callerName to value of static text 2 of notificationGroup
		return callerName
	else
		return ""
	end if
end tell
