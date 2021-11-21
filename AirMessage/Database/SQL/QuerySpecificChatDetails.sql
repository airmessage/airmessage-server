SELECT
	chat.guid AS "chat.guid",
	chat.display_name AS "chat.display_name",
	chat.service_name AS "chat.service_name",
	GROUP_CONCAT(handle.id) AS member_list
FROM
	chat
	JOIN chat_handle_join ON chat.ROWID = chat_handle_join.chat_id
	JOIN handle ON chat_handle_join.handle_id = handle.ROWID
WHERE
	chat.guid IN(?)
