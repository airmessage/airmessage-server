package me.tagavari.airmessageserver.server;

public enum LogType {
	DEBUG(0),
	INFO(1),
	NOTICE(2),
	ERROR(3),
	FAULT(4);
	
	public final int code;
	
	LogType(int code) {
		this.code = code;
	}
}