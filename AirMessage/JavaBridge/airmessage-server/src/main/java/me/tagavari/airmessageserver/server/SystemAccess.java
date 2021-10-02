package me.tagavari.airmessageserver.server;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.concurrent.ExecutionException;
import java.util.logging.Level;
import java.util.stream.Collectors;

public class SystemAccess {
    public static String processForResult(String command) {
        try {
            Process process = Runtime.getRuntime().exec(command);

            if(process.waitFor() == 0) {
                //Reading and returning the input
                BufferedReader in = new BufferedReader(new InputStreamReader(process.getInputStream()));
                return in.lines().collect(Collectors.joining());
            } else {
                //Logging the error
                try(BufferedReader in = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
                    String errorOutput = in.lines().collect(Collectors.joining());
                    Main.getLogger().log(Level.WARNING, "Unable to read process output: " + errorOutput);
                }
            }
        } catch(IOException | InterruptedException exception) {
            //Printing the stack trace
            Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
        }

        return null;
    }

    public static String readDeviceName() {
        return processForResult("scutil --get ComputerName");
    }

    public static boolean isProcessTranslated() {
        return "1".equals(processForResult("sysctl -n sysctl.proc_translated"));
    }

    public static String readProcessorArchitecture() {
        return processForResult("uname -p");
    }

    /**
     * Converts an image from one format to another
     * @param format The format to convert to
     * @param input The file to convert
     * @param output The file to write to
     */
    public static void convertImage(String format, File input, File output) throws IOException, InterruptedException, ExecutionException {
        Process process = Runtime.getRuntime().exec(new String[]{"sips", "--setProperty", "format", format, input.getPath(), "--out", output.getPath()});
        int exitCode = process.waitFor();
        if(exitCode != 0) {
            //Logging the error
            try(BufferedReader in = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
                String errorOutput = in.lines().collect(Collectors.joining());
                throw new ExecutionException(errorOutput, null);
            }
        }
    }

    /**
     * Converts an audio file from one format to another
     * @param fileFormat The file format to convert to
     * @param dataFormat The data format to convert to
     * @param input The file to convert
     * @param output The file to write to
     */
    public static void convertAudio(String fileFormat, String dataFormat, File input, File output) throws IOException, InterruptedException, ExecutionException {
        Process process = Runtime.getRuntime().exec(new String[]{"afconvert", "-f", fileFormat, "-d", dataFormat, input.getPath(), "-o", output.getPath()});
        int exitCode = process.waitFor();
        if(exitCode != 0) {
            //Logging the error
            try(BufferedReader in = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
                String errorOutput = in.lines().collect(Collectors.joining());
                throw new ExecutionException(errorOutput, null);
            }
        }
    }
}