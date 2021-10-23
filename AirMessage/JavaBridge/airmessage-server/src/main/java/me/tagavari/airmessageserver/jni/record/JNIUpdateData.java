package me.tagavari.airmessageserver.jni.record;

/**
 * A record that represents a server update.
 *
 * The ID is used to track different updates, such as if the client tries to tell the
 * server to install an update that's different from its current pending update,
 * the discrepancy can be detected.
 *
 * If remoteInstallable is false, the user will be notified of the update, but will
 * be instructed to follow through on their Mac, rather than offering a way to load
 * the update remotely.
 */
public record JNIUpdateData(int id, String version, String notes, boolean remoteInstallable) {
}