package me.tagavari.airmessageserver.server;

public enum ServerState {
	SETUP(1, "message.status.waiting", null, Constants.typeStatus),
	STARTING(2, "message.status.starting", null, Constants.typeStatus),
	CONNECTING(3, "message.status.connecting", null, Constants.typeStatus),
	RUNNING(4, "message.status.running", null, Constants.typeStatus),
	STOPPED(5, "message.status.stopped", null, Constants.typeStatus),
	
	ERROR_DATABASE(100, "message.status.error.database", "message.disk_access_error", Constants.typeError), //Couldn't connect to database
	
	ERROR_INTERNAL(101, "message.status.error.internal", "message.error.connect.internal", Constants.typeError), //Internal error
	ERROR_EXTERNAL(102, "message.status.error.external", "message.error.connect.external", Constants.typeError), //External error
	ERROR_INTERNET(103, "message.status.error.internet", "message.error.connect.internet", Constants.typeErrorRecoverable), //No internet connection
	
	ERROR_TCP_PORT(200, "message.status.error.port", null, Constants.typeError), //Port unavailable
	
	ERROR_CONN_BADREQUEST(300, "message.status.error.bad_request", "message.error.connect.bad_request", Constants.typeError), //Bad request
	ERROR_CONN_OUTDATED(301, "message.status.error.outdated", "message.error.connect.outdated", Constants.typeError), //Client out of date
	ERROR_CONN_VALIDATION(302, "message.status.error.account_validation", "message.error.connect.account_validation", Constants.typeError), //Account access not valid
	ERROR_CONN_TOKEN(303, "message.status.error.token_refresh", "message.error.connect.token_refresh", Constants.typeError), //Token refresh
	ERROR_CONN_SUBSCRIPTION(304, "message.status.error.no_enrollment", "message.error.connect.no_enrollment", Constants.typeError), //Not subscribed (not enrolled)
	ERROR_CONN_CONFLICT(305, "message.status.error.account_conflict", "message.error.connect.account_conflict", Constants.typeError); //Logged in from another location
	
	public final int code;
	public final String messageID;
	public final String messageIDLong;
	public final int type;
	
	ServerState(int code, String messageID, String messageIDLong, int type) {
		this.code = code;
		this.messageID = messageID;
		this.messageIDLong = messageIDLong;
		this.type = type;
	}
	
	public static class Constants {
		public static final int typeStatus = 0;
		public static final int typeError = 1;
		public static final int typeErrorRecoverable = 2;
	}
}