package me.tagavari.airmessageserver.jni;

import me.tagavari.airmessageserver.jni.exception.JNIAppleScriptException;
import me.tagavari.airmessageserver.jni.exception.JNINotSupportedException;

/**
 * JNIPreferences connects with native Messages functionality.
 * All functions are thread-safe.
 */
public class JNIMessage {
	/**
	 * Creates a new chat
	 * @param addresses The array of addresses to add to the chat
	 * @param service The service to create the chat over
	 * @return The GUID of the created chat, or NULL if the operation failed
	 * @throws JNIAppleScriptException If the chat couldn't be created
	 */
	public static native String createChat(String[] addresses, String service) throws JNIAppleScriptException, JNINotSupportedException;
	
	/**
	 * Sends a message to an existing chat
	 * @param chatGUID The GUID of the chat to send a message to
	 * @param message The message text to send
	 * @throws JNIAppleScriptException If the message failed to send
	 */
	public static native void sendExistingMessage(String chatGUID, String message) throws JNIAppleScriptException, JNINotSupportedException;
	
	/**
	 * Creates a new chat, and sends a message to it
	 * @param addresses The array of addresses to add to the chat
	 * @param service The service to create the chat over
	 * @param message The message text to send
	 * @throws JNIAppleScriptException If the message failed to send
	 */
	public static native void sendNewMessage(String[] addresses, String service, String message) throws JNIAppleScriptException, JNINotSupportedException;
	
	/**
	 * Sends a file to an existing chat
	 * @param chatGUID The GUID of the chat to send a message to
	 * @param filePath The path to the file to send
	 * @throws JNIAppleScriptException If the message failed to send
	 */
	public static native void sendExistingFile(String chatGUID, String filePath) throws JNIAppleScriptException, JNINotSupportedException;
	
	/**
	 * Creates a new chat, and sends a message to it
	 * @param addresses The array of addresses to add to the chat
	 * @param service The service to create the chat over
	 * @param filePath The path to the file to send
	 * @throws JNIAppleScriptException If the message failed to send
	 */
	public static native void sendNewFile(String[] addresses, String service, String filePath) throws JNIAppleScriptException, JNINotSupportedException;
}
