package me.tagavari.airmessageserver.connection.connect;

import java.nio.ByteBuffer;

public interface ConnectionListener {
	/**
	 * Called when a connection with Connect servers is established
	 */
	void handleConnect();
	
	/**
	 * Called when a connection with Connect servers is lost
	 * @param code The disconnection code
	 * @param reason The reason description
	 */
	void handleDisconnect(int code, String reason);
	
	/**
	 * Called when a new message is received
	 * @param bytes This message's body content
	 */
	void processData(ByteBuffer bytes);
}