package me.tagavari.airmessageserver.server;

public enum ServerState {
	SETUP(1, Constants.typeStatus),
	STARTING(2, Constants.typeStatus),
	CONNECTING(3, Constants.typeStatus),
	RUNNING(4, Constants.typeStatus),
	STOPPED(5, Constants.typeStatus),
	
	ERROR_DATABASE(100, Constants.typeError), //Couldn't connect to database
	
	ERROR_INTERNAL(101, Constants.typeError), //Internal error
	ERROR_EXTERNAL(102, Constants.typeError), //External error
	ERROR_INTERNET(103, Constants.typeErrorRecoverable), //No internet connection
	
	ERROR_TCP_PORT(200, Constants.typeError), //Port unavailable
	
	ERROR_CONN_BADREQUEST(300, Constants.typeError), //Bad request
	ERROR_CONN_OUTDATED(301, Constants.typeError), //Client out of date
	ERROR_CONN_VALIDATION(302, Constants.typeError), //Account access not valid
	ERROR_CONN_TOKEN(303, Constants.typeError), //Token refresh
	ERROR_CONN_SUBSCRIPTION(304, Constants.typeError), //Not subscribed (not enrolled)
	ERROR_CONN_CONFLICT(305, Constants.typeError); //Logged in from another location
	
	public final int code;
	public final int type;
	
	ServerState(int code, int type) {
		this.code = code;
		this.type = type;
	}
	
	public static class Constants {
		public static final int typeStatus = 0;
		public static final int typeError = 1;
		public static final int typeErrorRecoverable = 2;
	}
}