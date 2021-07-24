package me.tagavari.airmessageserver.jni.exception;

import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.exception.AppleScriptException;
import me.tagavari.airmessageserver.server.Constants;

public class JNINotSupportedException extends AppleScriptException {
	private final String noSupportVer;
	
	public JNINotSupportedException(String noSupportVer) {
		super("Not supported beyond macOS " + noSupportVer);
		this.noSupportVer = noSupportVer;
	}
	
	public String getNoSupportVer() {
		return noSupportVer;
	}
	
	@Override
	public Constants.Tuple<Integer, String> getSendErrorDetails() {
		return new Constants.Tuple<>(CommConst.nstSendResultScriptError, null);
	}
	
	@Override
	public Constants.Tuple<Integer, String> getCreateChatErrorDetails() {
		return new Constants.Tuple<>(CommConst.nstCreateChatScriptError, null);
	}
}