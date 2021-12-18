--Sends a message directly to a single recipient, works on macOS 11.0+
on main(address, serviceType, message, isFile)
	if isFile then
		set message to POSIX file message
	end if
	
	tell application "Messages"
		--Get the service
		if serviceType is "iMessage" then
			set targetService to 1st service whose service type = iMessage
		else
			set targetService to service serviceType
		end if
		
		--Get the participant
		set targetParticipant to participant address of targetService
		
		--Send the message
		send message to targetParticipant
	end tell
end main
