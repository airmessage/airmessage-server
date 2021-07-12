package me.tagavari.airmessageserver.connection.direct;

interface ReaderThreadListener {
	/**
	 * Called when a new message is received
	 * @param data This message's body content
	 * @param isEncrypted True if this message is encrypted
	 */
	void processData(byte[] data, boolean isEncrypted);
	
	/**
	 * Called when an exception occurs in the connection, and the connection must be killed
	 * @param cleanup TRUE if this connection should be closed gracefully, notifying the receiving party
	 */
	void cancelConnection(boolean cleanup);
}