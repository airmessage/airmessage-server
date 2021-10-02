package me.tagavari.airmessageserver.helper;

import java.util.Optional;

public class FileHelper {
    /**
     * Gets an extension from a file name
     */
    public static Optional<String> getExtensionByStringHandling(String filename) {
        return Optional.ofNullable(filename)
                .filter(f -> f.contains("."))
                .map(f -> f.substring(filename.lastIndexOf(".") + 1).toLowerCase());
    }
}