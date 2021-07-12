package me.tagavari.airmessageserver.jni;

/**
 * JNIPreferences connects with NSUserDefaults and Keychain on macOS.
 * All functions are thread-safe.
 */
public class JNIPreferences {
	/**
	 * Gets the server port
	 */
	public static native int getServerPort();
	
	/**
	 * Gets the user's selected account type, or -1 if unavailable
	 */
	public static native int getAccountType();
	
	/**
	 * Gets the user's password
	 */
	public static native String getPassword();
	
	/**
	 * Gets the installation ID of this device
	 */
	public static native String getInstallationID();
}