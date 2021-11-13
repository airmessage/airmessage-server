package me.tagavari.airmessageserver.connection;

public class CommConst {
	//Transmission header values
	public static final int mmCommunicationsVersion = 5;
	public static final int mmCommunicationsSubVersion = 5;
	
	//NHT - Net header type
	public static final int nhtClose = 0;
	public static final int nhtPing = 1;
	public static final int nhtPong = 2;
	
	public static final int nhtInformation = 100;
	public static final int nhtAuthentication = 101;
	
	public static final int nhtMessageUpdate = 200;
	public static final int nhtTimeRetrieval = 201;
	public static final int nhtIDRetrieval = 202;
	public static final int nhtMassRetrieval = 203;
	public static final int nhtMassRetrievalFile = 204;
	public static final int nhtMassRetrievalFinish = 205;
	public static final int nhtConversationUpdate = 206;
	public static final int nhtModifierUpdate = 207;
	public static final int nhtAttachmentReq = 208;
	public static final int nhtAttachmentReqConfirm = 209;
	public static final int nhtAttachmentReqFail = 210;
	public static final int nhtIDUpdate = 211;
	
	public static final int nhtLiteConversationRetrieval = 300;
	public static final int nhtLiteThreadRetrieval = 301;
	
	public static final int nhtSendResult = 400;
	public static final int nhtSendTextExisting = 401;
	public static final int nhtSendTextNew = 402;
	public static final int nhtSendFileExisting = 403;
	public static final int nhtSendFileNew = 404;
	public static final int nhtCreateChat = 405;
	
	public static final int nhtSoftwareUpdateListing = 500;
	public static final int nhtSoftwareUpdateInstall = 501;
	public static final int nhtSoftwareUpdateError = 502;
	
	public static final String hashAlgorithm = "MD5";
	
	//NST - Net subtype
	public static final int nstAuthenticationOK = 0;
	public static final int nstAuthenticationUnauthorized = 1;
	public static final int nstAuthenticationBadRequest = 2;
	
	public static final int nstSendResultOK = 0;
	public static final int nstSendResultScriptError = 1; //Some unknown AppleScript error
	public static final int nstSendResultBadRequest = 2; //Invalid data received
	public static final int nstSendResultUnauthorized = 3; //System rejected request to send message
	public static final int nstSendResultNoConversation = 4; //A valid conversation wasn't found
	public static final int nstSendResultRequestTimeout = 5; //File data blocks stopped being received
	
	public static final int nstAttachmentReqNotFound = 1; //File GUID not found
	public static final int nstAttachmentReqNotSaved = 2; //File (on disk) not found
	public static final int nstAttachmentReqUnreadable = 3; //No access to file
	public static final int nstAttachmentReqIO = 4; //IO error
	
	public static final int nstCreateChatOK = 0;
	public static final int nstCreateChatScriptError = 1; //Some unknown AppleScript error
	public static final int nstCreateChatBadRequest = 2; //Invalid data received
	public static final int nstCreateChatUnauthorized = 3; //System rejected request to send message
	
	//Timeouts
	public static final long handshakeTimeout = 10 * 1000; //10 seconds
	public static final long pingTimeout = 30 * 1000; //30 seconds
	public static final long keepAliveMillis = 30 * 60 * 1000; //30 minutes
	
	public static final long maxPacketAllocation = 50 * 1024 * 1024; //50 MB
	
	public static final int transmissionCheckLength = 32;
}
