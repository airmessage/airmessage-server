SELECT max(message.ROWID),
       message.guid,
       message.is_sent,
       message.is_delivered,
       message.is_read,
       message.date_read,
       chat.ROWID
FROM message
    JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
    JOIN chat ON chat_message_join.chat_id = chat.ROWID
WHERE message.is_from_me IS TRUE
GROUP BY chat.ROWID