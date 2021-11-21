SELECT %1$@ /* Fields */
FROM message
    JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
    JOIN chat ON chat_message_join.chat_id = chat.ROWID
    LEFT OUTER JOIN handle AS sender_handle ON message.handle_id = sender_handle.ROWID
    LEFT OUTER JOIN handle AS other_handle ON message.other_handle = other_handle.ROWID
%2$@ /* Extra query statements */
