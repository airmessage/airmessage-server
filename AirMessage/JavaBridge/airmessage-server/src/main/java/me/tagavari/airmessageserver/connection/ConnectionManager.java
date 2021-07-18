package me.tagavari.airmessageserver.connection;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.connect.DataProxyConnect;
import me.tagavari.airmessageserver.connection.direct.DataProxyTCP;
import me.tagavari.airmessageserver.constants.AccountType;
import me.tagavari.airmessageserver.jni.JNIPreferences;

/**
 * Controls the server connection
 * Handles interfacing between the data proxy and the data handler
 */
public class ConnectionManager {
	private static DataProxy dataProxy;
	private static CommunicationsManager communicationsManager;
	
	public static void setDataProxy(DataProxy dataProxy) {
		ConnectionManager.dataProxy = dataProxy;
		
		Sentry.setTag("protocol_proxy", dataProxy.getDisplayName().toLowerCase());
	}
	
	public static void start() {
		//Returning if there is already an active process
		if(communicationsManager != null && communicationsManager.isRunning()) return;
		
		//Starting the communications manager
		communicationsManager = new CommunicationsManager(dataProxy);
		communicationsManager.start();
	}
	
	public static void stop() {
		//Returning if there is no active process
		if(communicationsManager == null || !communicationsManager.isRunning()) return;
		
		//Stopping the communications manager
		communicationsManager.stop();
	}
	
	public static CommunicationsManager getCommunicationsManager() {
		return communicationsManager;
	}
	
	public static DataProxy<ClientRegistration> activeProxy() {
		return communicationsManager.getDataProxy();
	}
	
	public static int getConnectionCount() {
		if(communicationsManager == null || !communicationsManager.isRunning()) return 0;
		return communicationsManager.getDataProxy().getConnections().size();
	}
}