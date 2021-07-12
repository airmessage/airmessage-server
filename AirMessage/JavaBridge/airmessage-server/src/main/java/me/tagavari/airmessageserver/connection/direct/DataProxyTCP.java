package me.tagavari.airmessageserver.connection.direct;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.connection.DataProxy;
import me.tagavari.airmessageserver.connection.EncryptionHelper;
import me.tagavari.airmessageserver.server.Constants;
import me.tagavari.airmessageserver.server.Main;
import me.tagavari.airmessageserver.server.ServerState;

import java.net.ServerSocket;
import java.security.GeneralSecurityException;
import java.util.*;
import java.util.logging.Level;

public class DataProxyTCP extends DataProxy<ClientSocket> implements ListenerThreadListener {
	//Creating the state values
	private boolean serverRunning = false;
	private final List<ClientSocket> connectionList = Collections.synchronizedList(new ArrayList<>());
	
	private final int port; //The port to run the next server on
	private int launchedPort = -1; //The port the server is currently running on
	
	//Creating the thread values
	private ListenerThread listenerThread;
	private WriterThread writerThread;
	
	public DataProxyTCP(int port) {
		this.port = port;
	}
	
	@Override
	public void startServer() {
		//Returning if the server is already running
		if(serverRunning) return;
		
		//Returning if the requested port is already bound
		if(!Constants.checkPortAvailability(port)) {
			notifyStop(ServerState.ERROR_TCP_PORT);
			return;
		}
		
		try {
			//Creating the server socket
			ServerSocket serverSocket = new ServerSocket(port);
			
			//Starting the listener thread
			listenerThread = new ListenerThread(serverSocket, this);
			listenerThread.start();
		} catch(Exception exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			notifyStop(ServerState.ERROR_INTERNAL);
			return;
		}
		
		//Starting the writer thread
		writerThread = new WriterThread(connectionList);
		writerThread.start();
		
		//Setting the port
		serverRunning = true;
		launchedPort = port;
		
		//Notifying the listeners
		notifyStart();
	}
	
	@Override
	public void acceptClient(ClientSocket client) {
		//Adding the client
		connectionList.add(client);
		
		//Notifying the communications manager
		notifyOpen(client);
	}
	
	@Override
	public void processData(ClientSocket client, byte[] data, boolean isEncrypted) {
		//Decrypting the data
		if(isEncrypted) {
			try {
				data = EncryptionHelper.decrypt(data);
			} catch(GeneralSecurityException exception) {
				Main.getLogger().log(Level.WARNING, "Failed to decrypt incoming message / " + exception.getMessage(), exception);
				return;
			}
		}
		
		//Notifying the communications manager
		notifyMessage(client, data, isEncrypted);
	}
	
	@Override
	public void cancelConnection(ClientSocket client, boolean cleanup) {
		if(cleanup) ConnectionManager.getCommunicationsManager().initiateClose(client);
		else disconnectClient(client);
	}
	
	@Override
	public void stopServer() {
		//Returning if the server isn't running
		if(!serverRunning) return;
		
		//Stopping the threads
		if(listenerThread != null) listenerThread.closeAndInterrupt();
		if(writerThread != null) writerThread.interrupt();
		
		//Closing connected client connections
		for(ClientSocket client : new HashSet<>(connectionList)) client.disconnect();
		
		//Updating the server state
		serverRunning = false;
		
		//Notifying the listeners
		notifyStop(ServerState.STOPPED);
	}
	
	@Override
	public void sendMessage(ClientSocket client, byte[] content, boolean encrypt, Runnable sentRunnable) {
		//Encrypting the content if requested
		if(encrypt) {
			try {
				content = EncryptionHelper.encrypt(content);
			} catch(GeneralSecurityException exception) {
				Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
				Sentry.captureException(exception);
				return;
			}
		}
		
		//Sending the packet
		if(writerThread != null) writerThread.sendPacket(new WriterThread.PacketStruct(client, content, encrypt, sentRunnable));
	}
	
	@Override
	public void sendPushNotification(int version, byte[] payload) {
		//Not supported
	}
	
	@Override
	public void disconnectClient(ClientSocket client) {
		//Disconnecting the client
		client.disconnect();
		
		//Unlisting the client's connection
		connectionList.remove(client);
		
		//Notifying the communications manager
		notifyClose(client);
	}
	
	@Override
	public Collection<ClientSocket> getConnections() {
		return connectionList;
	}
	
	@Override
	public boolean requiresAuthentication() {
		return true;
	}
	
	@Override
	public boolean requiresPersistence() {
		return true;
	}
	
	@Override
	public String getDisplayName() {
		return "Direct";
	}
}