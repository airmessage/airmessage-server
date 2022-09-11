SELECT message.ROWID as "message.ROWID",
       message.guid AS "message.guid",
       message.part_count AS "message.part_count",
       message.message_summary_info AS "message.message_summary_info",
       chat.ROWID AS "chat.ROWID"
FROM message
WHERE message.date_edited > ?
%1$@ /* Extra query statements */
GROUP BY chat.ROWID
