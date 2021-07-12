package me.tagavari.airmessageserver.connection.direct;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.server.Constants;
import me.tagavari.airmessageserver.server.Main;

import javax.net.ssl.SSLException;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.net.SocketException;
import java.util.logging.Level;

class ReaderThread extends Thread {
	private final DataInputStream inputStream;
	private final ReaderThreadListener listener;
	
	ReaderThread(DataInputStream inputStream, ReaderThreadListener listener) {
		this.inputStream = inputStream;
		this.listener = listener;
	}
	
	@Override
	public void run() {
		while(!isInterrupted()) {
			try {
				//Reading the header data
				int contentLen = inputStream.readInt();
				boolean isEncrypted = inputStream.readBoolean();
				
				//Checking if the content length is greater than the maximum packet allocation
				if(contentLen > CommConst.maxPacketAllocation) {
					//Logging the error
					Main.getLogger().log(Level.WARNING, "Rejecting large packet (size " + contentLen + ")");
					Sentry.addBreadcrumb("Rejecting large packet (size " + contentLen + ")", Constants.sentryBCatPacket);
					
					//Closing the connection
					listener.cancelConnection(true);
					return;
				}
				
				//Reading the content
				byte[] content = new byte[contentLen];
				inputStream.readFully(content);
				
				//Processing the data
				listener.processData(content, isEncrypted);
			} catch(OutOfMemoryError exception) {
				//Logging the error
				Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
				Sentry.captureException(exception);
				
				//Closing the connection
				listener.cancelConnection(true);
				
				//Breaking
				break;
			} catch(SocketException | SSLException | EOFException | RuntimeException exception) {
				Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
				
				//A low-level socket exception occurred, close forcefully
				listener.cancelConnection(false);
				
				//Breaking
				break;
			} catch(IOException exception) {
				//Logging the error
				Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
				
				//Closing the connection
				listener.cancelConnection(true);
				
				//Breaking
				break;
			}
		}
	}
}