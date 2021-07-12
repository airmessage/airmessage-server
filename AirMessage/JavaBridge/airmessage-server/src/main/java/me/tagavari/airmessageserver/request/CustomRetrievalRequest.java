package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;
import me.tagavari.airmessageserver.server.DatabaseManager;

public class CustomRetrievalRequest extends DBRequest {
	public final DatabaseManager.RetrievalFilter filter;
	public final int messageResponseType;
	
	public CustomRetrievalRequest(ClientRegistration connection, DatabaseManager.RetrievalFilter filter, int messageResponseType) {
		super(connection);
		this.filter = filter;
		this.messageResponseType = messageResponseType;
	}
}