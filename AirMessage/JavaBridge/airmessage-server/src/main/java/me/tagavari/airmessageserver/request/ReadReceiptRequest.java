package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

//Requests read receipts since a certain time
public class ReadReceiptRequest extends DBRequest {
	public final long timeSince;
	
	public ReadReceiptRequest(ClientRegistration connection, long timeSince) {
		super(connection);
		this.timeSince = timeSince;
	}
}