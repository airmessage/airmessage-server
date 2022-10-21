SELECT message.ROWID as "message.ROWID",
       message.guid AS "message.guid",
       message.message_summary_info AS "message.message_summary_info",
       chat.ROWID AS "chat.ROWID"
FROM message
    LEFT OUTER JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
    LEFT OUTER JOIN chat ON chat_message_join.chat_id = chat.ROWID
WHERE message.date_edited > ?
%1$@ /* Extra query statements */
GROUP BY chat.ROWID
