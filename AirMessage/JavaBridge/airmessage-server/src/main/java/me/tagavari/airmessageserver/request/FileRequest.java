package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public class FileRequest extends DBRequest {
	public final String fileGuid;
	public final short requestID;
	public final int chunkSize;
	
	public FileRequest(ClientRegistration connection, String fileGuid, short requestID, int chunkSize) {
		super(connection);
		
		this.fileGuid = fileGuid;
		this.requestID = requestID;
		this.chunkSize = chunkSize;
	}
}