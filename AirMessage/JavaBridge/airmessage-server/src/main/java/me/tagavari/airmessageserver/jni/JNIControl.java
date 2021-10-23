package me.tagavari.airmessageserver.jni;

import me.tagavari.airmessageserver.connection.ClientRegistration;
import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.jni.record.JNIClientRegistration;
import me.tagavari.airmessageserver.server.Main;

/**
 * JNIControl receives updates from the native app.
 */
public class JNIControl {
	/**
	 * Starts the server
	 */
	public static void onStartServer() {
		Main.startServer();
	}
	
	/**
	 * Stops the server and puts it back in setup mode
	 */
	public static void onStopServer() {
		//Main.setServerState(ServerState.SETUP);
		ConnectionManager.stop();
	}
	
	/**
	 * Gets an array of connected clients
	 */
	public static JNIClientRegistration[] getClients() {
		return ConnectionManager.getCommunicationsManager().getDataProxy().getConnections()
				.stream()
				.map((client) -> new JNIClientRegistration(client.getInstallationID(), client.getClientName(), client.getPlatformID()))
				.toArray(JNIClientRegistration[]::new);
	}
}
