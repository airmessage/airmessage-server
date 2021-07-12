package me.tagavari.airmessageserver.jni;

import me.tagavari.airmessageserver.server.Main;

/**
 * JNIControl receives updates from the native app.
 */
public class JNIControl {
	/**
	 * Starts the server from the "retry" button
	 */
	public static void onStartServer() {
		Main.startServer();
	}
}