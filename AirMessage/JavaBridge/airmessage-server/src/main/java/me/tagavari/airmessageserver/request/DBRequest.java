package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public abstract class DBRequest {
	public final ClientRegistration connection;
	
	public DBRequest(ClientRegistration connection) {
		this.connection = connection;
	}
}