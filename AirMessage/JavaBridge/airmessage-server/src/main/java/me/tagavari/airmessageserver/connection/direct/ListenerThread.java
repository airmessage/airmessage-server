package me.tagavari.airmessageserver.connection.direct;

import me.tagavari.airmessageserver.server.Main;

import java.io.IOException;
import java.net.ServerSocket;
import java.util.logging.Level;

class ListenerThread extends Thread {
	//Creating the server values
	private final ServerSocket serverSocket;
	private final ListenerThreadListener callbacks;
	
	ListenerThread(ServerSocket serverSocket, ListenerThreadListener callbacks) {
		//Setting the socket
		this.serverSocket = serverSocket;
		
		//Setting the callbacks
		this.callbacks = callbacks;
	}
	
	@Override
	public void run() {
		//Accepting new connections
		while(!isInterrupted()) {
			try {
				ClientSocket client = new ClientSocket(serverSocket.accept(), callbacks);
				acceptClient(client);
			} catch(IOException exception) {
				Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			}
		}
	}
	
	private void acceptClient(ClientSocket client) {
		callbacks.acceptClient(client);
	}
	
	void closeAndInterrupt() {
		//Closing the socket
		try {
			serverSocket.close();
		} catch(IOException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
		
		//Interrupting the thread
		interrupt();
	}
}