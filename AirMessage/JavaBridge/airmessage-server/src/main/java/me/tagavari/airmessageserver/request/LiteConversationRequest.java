package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public class LiteConversationRequest extends DBRequest {
	public LiteConversationRequest(ClientRegistration connection) {
		super(connection);
	}
}