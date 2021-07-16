package me.tagavari.airmessageserver.jni;

import java.io.PrintWriter;
import java.io.StringWriter;

public class JNIUtil {
	/**
	 * Helps JNI inspect an exception by returning its description
	 */
	public static String describeThrowable(Throwable throwable) {
		StringWriter stringWriter = new StringWriter();
		PrintWriter printWriter = new PrintWriter(stringWriter);
		throwable.printStackTrace(printWriter);
		return stringWriter.toString();
	}
}