package me.tagavari.airmessageserver.server;

import me.tagavari.airmessageserver.jni.record.JNIUpdateData;

public class UpdateManager {
	private static JNIUpdateData currentUpdateData = null;
	
	/**
	 * Sets the current update data
	 * @param currentUpdateData The current pending update data,
	 *                          or NULL if no update is available.
	 */
	public static void setCurrentUpdateData(JNIUpdateData currentUpdateData) {
		UpdateManager.currentUpdateData = currentUpdateData;
	}
}