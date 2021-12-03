--Only works on macOS 10.15 or below
on main(addressList, serviceType, message, isFile)
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
		
		--Create the participants
		set participantList to {}
		repeat with address in addressList
			set end of participantList to buddy address of targetService
		end repeat
		
		--Create the chat
		set createdChat to make new text chat with properties {participants: participantList}
		
		--Send the message
		send message to createdChat
	end tell
end main
