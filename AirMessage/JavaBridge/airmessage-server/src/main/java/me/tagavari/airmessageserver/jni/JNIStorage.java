package me.tagavari.airmessageserver.jni;

import java.io.File;

/**
 * JNIPreferences connects with AppKit documents and cache directory paths.
 * All functions are thread-safe.
 */
public class JNIStorage {
	/**
	 * Gets the app's documents directory
	 */
	public static native File getDocumentsDirectory();
	
	/**
	 * Gets the app's cache directory
	 */
	public static native File getCacheDirectory();
}