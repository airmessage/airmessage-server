package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public class ConversationInfoRequest extends DBRequest {
	public final String[] conversationsGUIDs;
	
	public ConversationInfoRequest(ClientRegistration connection, String[] conversationsGUIDs) {
		super(connection);
		
		this.conversationsGUIDs = conversationsGUIDs;
	}
}