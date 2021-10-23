package me.tagavari.airmessageserver.jni;

import me.tagavari.airmessageserver.jni.record.JNIUpdateData;

public class JNIUpdate {
	/**
	 * Gets the current pending update, or NULL if there is none
	 */
	public static native JNIUpdateData getUpdate();
	
	/**
	 * Install the pending update with the specified ID.
	 * @param updateID The ID of the pending update to install
	 * @return Whether the update is starting to be installed
	 */
	public static native boolean installUpdate(int updateID);
}