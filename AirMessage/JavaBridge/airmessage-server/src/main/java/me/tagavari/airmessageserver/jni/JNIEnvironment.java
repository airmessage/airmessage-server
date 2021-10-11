package me.tagavari.airmessageserver.jni;

/**
 * JNIPreferences connects with constant app and environment information.
 * All functions are thread-safe.
 */
public class JNIEnvironment {
	/**
	 * Gets the human-readable app version string
	 */
	public static native String getAppVersion();
	
	/**
	 * Gets the app version code
	 */
	public static native int getAppVersionCode();
}