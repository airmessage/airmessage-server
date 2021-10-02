package me.tagavari.airmessageserver.connection.connect;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.server.Main;
import me.tagavari.airmessageserver.server.PropertiesManager;
import org.java_websocket.client.WebSocketClient;
import org.java_websocket.drafts.Draft_6455;
import org.java_websocket.exceptions.WebsocketNotConnectedException;
import org.java_websocket.handshake.ServerHandshake;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Level;

class ConnectWebSocketClient extends WebSocketClient {
	//Creating the constants
	private static final int connectTimeout = 8 * 1000; //8 seconds
	
	//Creating the callbacks
	private final ConnectionListener connectionListener;
	
	static ConnectWebSocketClient createInstance(String installationID, String idToken, ConnectionListener connectionListener) {
		Map<String, String> headers = new HashMap<>();
		headers.put("Origin", "app");
		
		String query = new QueryBuilder()
				.with("communications", NHT.commVer)
				.with("is_server", true)
				.with("installation_id", installationID)
				.with("id_token", idToken)
				.toString();
		
		try {
			return new ConnectWebSocketClient(new URI(PropertiesManager.getConnectEndpoint() + "?" + query), headers, connectTimeout, connectionListener);
		} catch(URISyntaxException exception) {
			Sentry.captureException(exception);
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			return null;
		}
	}
	
	public ConnectWebSocketClient(URI serverUri, Map<String, String> httpHeaders, int connectTimeout, ConnectionListener connectionListener) {
		super(serverUri, new Draft_6455(), httpHeaders, connectTimeout);
		
		this.connectionListener = connectionListener;
		
		setConnectionLostTimeout(10 * 60); //Every 10 mins
	}
	
	/**
	 * Attempts to send data to this client,
	 * and returns instead of throwing an exception
	 * @param data The data to send
	 * @return TRUE if this message was sent
	 */
	public boolean sendSafe(byte[] data) {
		try {
			send(data);
		} catch(WebsocketNotConnectedException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			return false;
		}
		
		return true;
	}
	
	@Override
	public void onOpen(ServerHandshake handshakeData) {
		Main.getLogger().log(Level.INFO, "Connection to Connect relay opened");
		connectionListener.handleConnect();
	}
	
	@Override
	public void onMessage(ByteBuffer bytes) {
		connectionListener.processData(bytes);
	}
	
	@Override
	public void onMessage(String message) {
	
	}
	
	@Override
	public void onClose(int code, String reason, boolean remote) {
		Main.getLogger().log(Level.INFO,  "Connection to Connect relay lost: " + code + " / " + reason);
		connectionListener.handleDisconnect(code, reason);
	}
	
	@Override
	public void onError(Exception exception) {
		Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
	}
}