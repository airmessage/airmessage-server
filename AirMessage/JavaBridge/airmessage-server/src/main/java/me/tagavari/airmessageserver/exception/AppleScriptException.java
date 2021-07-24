package me.tagavari.airmessageserver.exception;

import me.tagavari.airmessageserver.server.Constants;

public abstract class AppleScriptException extends Exception {
	public AppleScriptException() {
	}
	
	public AppleScriptException(String message) {
		super(message);
	}
	
	public AppleScriptException(String message, Throwable cause) {
		super(message, cause);
	}
	
	public AppleScriptException(Throwable cause) {
		super(cause);
	}
	
	public AppleScriptException(String message, Throwable cause, boolean enableSuppression, boolean writableStackTrace) {
		super(message, cause, enableSuppression, writableStackTrace);
	}
	
	public abstract Constants.Tuple<Integer, String> getSendErrorDetails();
	public abstract Constants.Tuple<Integer, String> getCreateChatErrorDetails();
}