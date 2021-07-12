package me.tagavari.airmessageserver.exception;

public class KeychainPermissionException extends Exception {
	public KeychainPermissionException() {
		super("User rejected Keychain access prompts");
	}
}