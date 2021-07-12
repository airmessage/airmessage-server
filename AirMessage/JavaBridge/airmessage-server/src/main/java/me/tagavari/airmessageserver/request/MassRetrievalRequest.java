package me.tagavari.airmessageserver.request;

import me.tagavari.airmessageserver.connection.ClientRegistration;

public class MassRetrievalRequest extends DBRequest {
	public final short requestID;
	public final boolean restrictMessages;
	public final long timeSinceMessages;
	public final boolean downloadAttachments;
	public final boolean restrictAttachments;
	public final long timeSinceAttachments;
	public final boolean restrictAttachmentsSizes;
	public final long attachmentSizeLimit;
	public String[] attachmentFilterWhitelist;
	public String[] attachmentFilterBlacklist;
	public boolean attachmentFilterDLOutside;
	
	public MassRetrievalRequest(ClientRegistration connection, short requestID, boolean restrictMessages, long timeSinceMessages, boolean downloadAttachments, boolean restrictAttachments, long timeSinceAttachments, boolean restrictAttachmentsSizes, long attachmentSizeLimit, String[] attachmentFilterWhitelist, String[] attachmentFilterBlacklist, boolean attachmentFilterDLOutside) {
		super(connection);
		this.requestID = requestID;
		this.restrictMessages = restrictMessages;
		this.timeSinceMessages = timeSinceMessages;
		this.downloadAttachments = downloadAttachments;
		this.restrictAttachments = restrictAttachments;
		this.timeSinceAttachments = timeSinceAttachments;
		this.restrictAttachmentsSizes = restrictAttachmentsSizes;
		this.attachmentSizeLimit = attachmentSizeLimit;
		this.attachmentFilterWhitelist = attachmentFilterWhitelist;
		this.attachmentFilterBlacklist = attachmentFilterBlacklist;
		this.attachmentFilterDLOutside = attachmentFilterDLOutside;
	}
}