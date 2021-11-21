SELECT
	chat.guid AS "chat.guid",
	chat.display_name AS "chat.display_name",
	chat.service_name AS "chat.service_name",
	GROUP_CONCAT(handle.id) AS member_list
FROM (
	SELECT
		chat.*,
		MAX(message.date) AS last_date
	FROM message
		JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
		JOIN chat ON chat_message_join.chat_id = chat.ROWID
	GROUP BY chat.ROWID
	) AS chat
	JOIN chat_handle_join ON chat.ROWID = chat_handle_join.chat_id
	JOIN handle ON chat_handle_join.handle_id = handle.ROWID
WHERE last_date > ?
GROUP BY chat.ROWID
