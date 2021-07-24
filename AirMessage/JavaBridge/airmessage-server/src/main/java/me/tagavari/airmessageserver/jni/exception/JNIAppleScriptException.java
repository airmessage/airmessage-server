package me.tagavari.airmessageserver.jni.exception;

import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.exception.AppleScriptException;
import me.tagavari.airmessageserver.server.Constants;

public class JNIAppleScriptException extends AppleScriptException {
	private final String errorMessage;
	private final int errorCode;
	
	public JNIAppleScriptException(String errorMessage, int errorCode) {
		super("Error " + errorCode + ": " + errorMessage);
		this.errorMessage = errorMessage;
		this.errorCode = errorCode;
	}
	
	public String getErrorMessage() {
		return errorMessage;
	}
	
	public int getErrorCode() {
		return errorCode;
	}
	
	@Override
	public Constants.Tuple<Integer, String> getSendErrorDetails() {
		int resultCode = switch(errorCode) {
			case Constants.asErrorCodeMessagesUnauthorized -> CommConst.nstSendResultUnauthorized;
			case Constants.asErrorCodeMessagesNoChat -> CommConst.nstSendResultNoConversation;
			default -> CommConst.nstSendResultScriptError;
		};
		return new Constants.Tuple<>(resultCode, "AppleScript error code " + errorCode + ": " + errorMessage);
	}
	
	@Override
	public Constants.Tuple<Integer, String> getCreateChatErrorDetails() {
		int resultCode = switch(errorCode) {
			case Constants.asErrorCodeMessagesUnauthorized -> CommConst.nstCreateChatUnauthorized;
			default -> CommConst.nstCreateChatScriptError;
		};
		return new Constants.Tuple<>(resultCode, "AppleScript error code " + errorCode + ": " + errorMessage);
	}
}
