package me.tagavari.airmessageserver.jni;

/**
 * JNIUserInterface updates the UI on the native side.
 */
public class JNIUserInterface {
	/**
	 * Updates the UI state
	 */
	public static native void updateUIState(int state);
	
	/**
	 * Updates the displayed connection count
	 */
	public static native void updateConnectionCount(int count);
}