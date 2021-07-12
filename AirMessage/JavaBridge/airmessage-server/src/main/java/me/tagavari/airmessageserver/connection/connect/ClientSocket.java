package me.tagavari.airmessageserver.connection.connect;

import me.tagavari.airmessageserver.connection.ClientRegistration;

class ClientSocket extends ClientRegistration {
	private final int connectionID;
	
	public ClientSocket(int connectionID) {
		this.connectionID = connectionID;
	}
	
	int getConnectionID() {
		return connectionID;
	}
}