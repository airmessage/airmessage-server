package me.tagavari.airmessageserver.helper;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.server.Constants;
import me.tagavari.airmessageserver.server.Main;
import me.tagavari.airmessageserver.server.SystemAccess;

import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.ExecutionException;
import java.util.logging.Level;

public class ConversionHelper {
    public static ConvertedFile convert(File file) {
        //Getting the file extension
        String fileExtension = FileHelper.getExtensionByStringHandling(file.getName()).orElse(null);

        //Checking if the file is HEIC (and we're running on a system version that supports handling it)
        if("heic".equals(fileExtension) && Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSHighSierraVersion) >= 0) {
            Main.getLogger().log(Level.INFO, "Converting file " + file.getPath() + " from HEIC");

            //Creating the convert directory if it doesn't exist
            if(Constants.convertDir.isFile()) Constants.convertDir.delete();
            if(!Constants.convertDir.exists()) Constants.convertDir.mkdir();

            //Converting the file to JPEG
            File targetFile = new File(Constants.convertDir, UUID.randomUUID() + ".jpeg");
            try {
                SystemAccess.convertImage("jpeg", file, targetFile);
            } catch(IOException | InterruptedException | ExecutionException exception) {
                //Log exception
                Sentry.captureException(exception);
                
                //Clean up
                targetFile.delete();
    
                //Return the original file
                return new ConvertedFile(file, false, null, null);
            }

            //Setting the file data
            String newFileName = file.getName().substring(0, file.getName().lastIndexOf(".")) + ".jpeg";
            return new ConvertedFile(targetFile, true, newFileName, "image/jpeg");
        }
        //Otherwise checking if the file is CAF (and we're running on a system version that supports handling it)
        else if("caf".equals(fileExtension) && Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSHighSierraVersion) >= 0) {
            Main.getLogger().log(Level.INFO, "Converting file " + file.getPath() + " from CAF");

            //Creating the convert directory if it doesn't exist
            if(Constants.convertDir.isFile()) Constants.convertDir.delete();
            if(!Constants.convertDir.exists()) Constants.convertDir.mkdir();

            //Converting the file
            File targetFile = new File(Constants.convertDir, UUID.randomUUID() + ".mp4");
            try {
                SystemAccess.convertAudio("mp4f", "aac", file, targetFile);
            } catch(IOException | InterruptedException | ExecutionException exception) {
                //Log exception
                Sentry.captureException(exception);
                
                //Clean up
                targetFile.delete();
    
                //Return the original file
                return new ConvertedFile(file, false, null, null);
            }

            String newFilename = file.getName().substring(0, file.getName().lastIndexOf(".")) + ".mp4";
            return new ConvertedFile(targetFile, true, newFilename, "audio/mp4");
        } else {
            //No conversion
            return new ConvertedFile(file, false, null, null);
        }
    }

    public static record ConvertedFile(
            File file, //The file to upload
            boolean converted, //Whether this file was converted, and the file should be deleted
            String updatedName, //The updated name of the converted file
            String updatedType //The updated type of the converted file
    ) implements Closeable {
        @Override
        public void close() throws IOException {
            if(converted) {
                file.delete();
            }
        }
    }
}