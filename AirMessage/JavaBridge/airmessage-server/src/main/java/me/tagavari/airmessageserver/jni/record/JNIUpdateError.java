package me.tagavari.airmessageserver.jni.record;

/**
 * A record that represents a software update error.
 */
public record JNIUpdateError(int code, String message) {
}
