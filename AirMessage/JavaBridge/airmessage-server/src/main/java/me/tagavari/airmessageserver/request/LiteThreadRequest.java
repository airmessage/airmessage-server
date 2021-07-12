package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public class LiteThreadRequest extends DBRequest {
	public final String conversationGUID;
	public final long firstMessageID;
	
	public LiteThreadRequest(ClientRegistration connection, String conversationGUID, long firstMessageID) {
		super(connection);
		this.conversationGUID = conversationGUID;
		this.firstMessageID = firstMessageID;
	}
}