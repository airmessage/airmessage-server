package me.tagavari.airmessageserver.connection.direct;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.ClientRegistration;
import me.tagavari.airmessageserver.server.Constants;
import me.tagavari.airmessageserver.server.Main;

import javax.net.ssl.SSLException;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.net.SocketException;
import java.util.logging.Level;

class ClientSocket extends ClientRegistration {
	private final Socket socket;
	private final ReaderThread readerThread;
	private final DataOutputStream outputStream;
	private final ListenerThreadListener callbacks;
	
	public ClientSocket(Socket socket, ListenerThreadListener listener) throws IOException {
		//Setting the socket information
		this.socket = socket;
		this.callbacks = listener;
		
		//Initializing the threads and streams
		readerThread = new ReaderThread(new DataInputStream(socket.getInputStream()), new ReaderThreadListener() {
			@Override
			public void processData(byte[] data, boolean isEncrypted) {
				listener.processData(ClientSocket.this, data, isEncrypted);
			}
			
			@Override
			public void cancelConnection(boolean cleanup) {
				listener.cancelConnection(ClientSocket.this, cleanup);
			}
		});
		readerThread.start();
		outputStream = new DataOutputStream(socket.getOutputStream());
		
		//Logging the connection
		Main.getLogger().info("Client connected from " + socket.getInetAddress().getHostName() + " (" + socket.getInetAddress().getHostAddress() + ")");
	}
	
	synchronized boolean sendDataSync(byte[] data, boolean isEncrypted) {
		if(!isConnected()) return false;
		
		try {
			outputStream.writeInt(data.length);
			outputStream.writeBoolean(isEncrypted);
			outputStream.write(data);
			outputStream.flush();
			
			return true;
		} catch(SocketException | SSLException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			if(isConnected() && Constants.checkDisconnected(exception)) callbacks.cancelConnection(this, false);
			
			return false;
		} catch(NullPointerException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			
			return false;
		} catch(IOException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			if(isConnected() && Constants.checkDisconnected(exception)) callbacks.cancelConnection(this, false);
			else Sentry.captureException(exception);
			
			return false;
		}
	}
	
	void disconnect() {
		//Cancelling timers
		cancelAllTimers();
		
		//Returning if the connection is not open
		if(!isConnected()) return;
		
		//Setting the connection as closed
		setConnected(false);
		
		try {
			//Closing the socket
			socket.close();
		} catch(IOException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
		
		//Finishing the reader thread
		readerThread.interrupt();
		
		//Logging the connection
		Main.getLogger().info("Client disconnected from " + socket.getInetAddress().getHostName() + " (" + socket.getInetAddress().getHostAddress() + ")");
	}
}