package me.tagavari.airmessageserver.jni;

import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.jni.record.JNIUpdateData;
import me.tagavari.airmessageserver.jni.record.JNIUpdateError;

public class JNIUpdate {
	/**
	 * Gets the current pending update, or NULL if there is none
	 */
	public static native JNIUpdateData getUpdate();
	
	/**
	 * Installs the pending update with the specified ID.
	 * @param updateID The ID of the pending update to install
	 * @return Whether the update is starting to be installed
	 */
	public static native boolean installUpdate(int updateID);
	
	/**
	 * Notifies connected clients that an update error occurred
	 */
	public static void notifyUpdateError(JNIUpdateError error) {
		ConnectionManager.getCommunicationsManager().sendMessageUpdateError(null, error);
	}
}