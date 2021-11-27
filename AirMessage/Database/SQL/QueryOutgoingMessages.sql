SELECT max(message.ROWID) as "message.ROWID",
       message.guid AS "message.guid",
       message.is_sent AS "message.is_sent",
       message.is_delivered AS "message.is_delivered",
       message.is_read AS "message.is_read",
       message.date_read AS "message.date_read",
       chat.ROWID AS "chat.ROWID"
FROM message
    JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
    JOIN chat ON chat_message_join.chat_id = chat.ROWID
WHERE message.is_from_me IS 1
%1$@ /* Extra query statements */
GROUP BY chat.ROWID
