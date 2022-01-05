SELECT
	chat.guid AS "chat.guid",
	chat.display_name AS "chat.display_name",
	chat.service_name AS "chat.service_name",
	message.text AS "message.text",
	message.date AS "message.date",
	message.is_from_me AS "message.is_from_me",
	handle.id AS "handle.id",
	sub2.member_list AS member_list,
	GROUP_CONCAT(attachment.mime_type) AS attachment_list
	%1$@ /* Extra fields, leading comma will be inserted */
FROM (
	/* Join chats to members, concat to member_list */
	SELECT
		sub1.*,
		GROUP_CONCAT(handle.id) AS member_list
	FROM (
		/* Select the most recent message per chat */
		SELECT
			chat.ROWID AS chat_id,
			message.ROWID AS message_id,
			MAX(message.date)
		FROM chat
		JOIN chat_message_join ON chat.ROWID = chat_message_join.chat_id
		JOIN message ON chat_message_join.message_id = message.ROWID
		WHERE message.item_type = 0
		GROUP BY chat.ROWID
	) AS sub1
	JOIN chat_handle_join ON chat_handle_join.chat_id = sub1.chat_id
	JOIN handle ON chat_handle_join.handle_id = handle.ROWID
	GROUP BY sub1.chat_id
) AS sub2
JOIN chat ON chat.ROWID = sub2.chat_id
JOIN message ON message.ROWID = sub2.message_id
LEFT JOIN message_attachment_join ON message_attachment_join.message_id = sub2.message_id
LEFT JOIN attachment ON message_attachment_join.attachment_id = attachment.ROWID
LEFT JOIN handle ON message.handle_id = handle.ROWID
GROUP BY chat.ROWID
ORDER BY message.date DESC
