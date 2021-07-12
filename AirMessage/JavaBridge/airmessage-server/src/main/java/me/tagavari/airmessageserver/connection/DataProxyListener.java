package me.tagavari.airmessageserver.connection;

import me.tagavari.airmessageserver.server.ServerState;

public interface DataProxyListener<C> {
	/**
	 * Called when the proxy is started successfully
	 */
	void onStart();
	
	/**
	 * Called when the proxy is paused
	 * This happens when a temporary, automatically recoverable error occurs in the proxy,
	 * such as a dropped connection. No user input is required to solve these problems,
	 * but this updates the UI so the user at least knows what's going on.
	 *
	 * This method cannot be called while the server is in setup mode, and should instead
	 * redirect to {@link #onStop(ServerState)} onStop()}.
	 * @param code The error code
	 */
	void onPause(ServerState code);
	
	/**
	 * Called when the proxy is stopped
	 * (either as directed or due to an exception)
	 * @param code The error code
	 */
	void onStop(ServerState code);
	
	/**
	 * Called when a new client is connected
	 * @param client The client that connected
	 */
	void onOpen(C client);
	
	/**
	 * Called when a client is disconnected
	 * @param client The client that disconnected
	 */
	void onClose(C client);
	
	/**
	 * Called when a message is received
	 * @param wasEncrypted True if this message was encrypted during transit (and probably contains sensitive content)
	 * @param client The client that sent the message
	 * @param content The message's body
	 */
	void onMessage(C client, byte[] content, boolean wasEncrypted);
}