on main(chatID, message, isFile)
	if isFile then
		set message to POSIX file message
	end if
	
	tell application "Messages"
		send message to chat id chatID
	end tell
end main
