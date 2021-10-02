package me.tagavari.airmessageserver.server;

import me.tagavari.airmessageserver.jni.JNIStorage;

import java.io.File;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.DatagramSocket;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.SocketException;
import java.util.Enumeration;
import java.util.Random;
import java.util.logging.Level;
import java.util.stream.Stream;

public class Constants {
	//Creating the version values
	public static final String SERVER_VERSION = "3.4.1";
	public static final int SERVER_VERSION_CODE = 25;
	
	//Creating the file values
	public static final File applicationSupportDir = JNIStorage.getDocumentsDirectory();
	public static final File uploadDir = new File(applicationSupportDir, "uploads");
	public static final File updateDir = new File(applicationSupportDir, "update");
	public static final File convertDir = new File(applicationSupportDir, "convert");
	
	//Creating the macOS version values
	public static final int[] macOSYosemiteVersion = {10, 10};
	public static final int[] macOSElCapitanVersion = {10, 11};
	public static final int[] macOSSierraVersion = {10, 12};
	public static final int[] macOSHighSierraVersion = {10, 13};
	public static final int[] macOSMojaveVersion = {10, 14};
	public static final int[] macOSCatalinaVersion = {10, 15};
	public static final int[] macOSBigSurVersion = {10, 16};
	
	//Creating the AppleScript error values
	public static final int asErrorCodeMessagesUnauthorized = -1743;
	public static final int asErrorCodeMessagesNoChat = -1728;
	
	//Creating the regex values
	static final String reExInteger = "^\\d+$";
	static final String regExSplitFilename = "\\.(?=[^.]+$)";
	
	//Creating the reporting values
	public static final String sentryBCatPacket = "packet-info";
	
	//Creating the other values
	static final int minPort = 0;
	static final int maxPort = 65535;
	
	public static File findFreeFile(File directory, String fileName) {
		return findFreeFile(directory, fileName, "_", 0);
	}
	
	public static File findFreeFile(File directory, String fileName, String separator, int startIndex) {
		//Creating the file
		File file = new File(directory, fileName);
		
		//Checking if the file directory doesn't exist
		if(!directory.exists()) {
			//Creating the directory
			directory.mkdir();
			
			//Returning the file
			return file;
		}
		
		//Getting the file name and extension
		String[] fileData = file.getName().split(regExSplitFilename);
		String baseFileName = fileData[0];
		String fileExtension = fileData.length > 1 ? fileData[1] : "";
		int currentIndex = startIndex;
		
		//Finding a free file
		while(file.exists()) file = new File(directory, baseFileName + separator + currentIndex++ + '.' + fileExtension);
		
		//Returning the file
		return file;
	}
	
	public static void recursiveDelete(File file) {
		if(file.isFile()) file.delete();
		else {
			File[] childFiles = file.listFiles();
			if(childFiles != null) for(File childFile : childFiles) recursiveDelete(childFile);
			file.delete();
		}
	}
	
	public static int[] getSystemVersion() {
		return parseVersionString(System.getProperty("os.version"));
	}
	
	public static int[] parseVersionString(String version) {
		return Stream.of(version.split("\\.")).mapToInt(Integer::parseInt).toArray();
	}
	
	/* Return values
	-1 / version 1 is smaller
	 0 / versions are equal
	 1 / version 1 is greater
	 */
	public static int compareVersions(int[] version1, int[] version2) {
		//Iterating over the arrays
		for(int i = 0; i < Math.max(version1.length, version2.length); i++) {
			//Comparing the version values
			int comparison = Integer.compare(i >= version1.length ? 0 : version1[i], i >= version2.length ? 0 : version2[i]);
			
			//Returning if the value is not 0
			if(comparison != 0) return comparison;
		}
		
		//Returning 0 (the loop finished, meaning that there was no difference)
		return 0;
	}
	
	static File getPrefsFile() {
		//Returning the preferences file path
		return new File(System.getProperty("user.home") + '/' + Constants.class.getPackage().getName());
	}
	
	static class ValueWrapper<T> {
		T value;
		
		ValueWrapper(T value) {
			this.value = value;
		}
	}
	
	public static String getDelimitedString(String[] list, String delimiter) {
		if(list.length == 0) return "";
		else if(list.length == 1) return list[0];
		
		StringBuilder stringBuilder = new StringBuilder();
		stringBuilder.append(list[0]);
		for(int i = 1; i < list.length; i++) stringBuilder.append(delimiter).append(list[i]);
		
		return stringBuilder.toString();
	}
	
	/**
	 * Checks to see if a specific port is available.
	 *
	 * @param port the port to check for availability
	 */
	public static boolean checkPortAvailability(int port) {
		//Returning if the port is out of range
		if(port < minPort || port > maxPort) throw new IllegalArgumentException("Invalid start port: " + port);
		
		//Attempting to bind the port
		try(ServerSocket serverSocket = new ServerSocket(port);
			DatagramSocket datagramSocket = new DatagramSocket(port)) {
			serverSocket.setReuseAddress(true);
			datagramSocket.setReuseAddress(true);
			
			//Returning true
			return true;
		} catch(IOException exception) {
			//An exception was thrown, port couldn't be bound
			Main.getLogger().log(Level.INFO, exception.getMessage(), exception);
		}
		
		//Returning false
		return false;
	}
	
	private static final String ALPHA_NUMERIC_STRING = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	public static String randomAlphaNumericString(int length) {
		StringBuilder builder = new StringBuilder();
		Random random = new Random();
		
		for(int i = 0; i < length; i++) builder.append(ALPHA_NUMERIC_STRING.charAt(random.nextInt(ALPHA_NUMERIC_STRING.length())));
		
		return builder.toString();
	}
	
	//Uses active network interface
	/* static String getMACAddress() {
		try {
			byte[] mac = NetworkInterface.getByInetAddress(InetAddress.getLocalHost()).getHardwareAddress();
			if(mac == null) return null;
			StringBuilder stringBuilder = new StringBuilder();
			for(int i = 0; i < mac.length; i++) stringBuilder.append(String.format("%02X%s", mac[i], (i < mac.length - 1) ? "-" : ""));
			return stringBuilder.toString();
		} catch(UnknownHostException | SocketException | NullPointerException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			return null;
		}
	} */
	
	//Uses first network interface
	static String getMACAddress() {
		try {
			Enumeration<NetworkInterface> interfaceList = NetworkInterface.getNetworkInterfaces();
			if(interfaceList == null) return null;
			while(interfaceList.hasMoreElements()) {
				NetworkInterface netInterface = interfaceList.nextElement();
				if(netInterface == null) continue;
				byte[] macAddress = netInterface.getHardwareAddress();
				if(macAddress == null) continue;
				
				StringBuilder stringBuilder = new StringBuilder();
				for(int i = 0; i < macAddress.length; i++) stringBuilder.append(String.format("%02X%s", macAddress[i], (i < macAddress.length - 1) ? "-" : ""));
				return stringBuilder.toString();
			}
			
			return null;
		} catch(SocketException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			return null;
		}
	}
	
	public static boolean checkDisconnected(IOException exception) {
		return exception.getMessage().toLowerCase().contains("broken pipe");
	}
	
	public static boolean checkDisconnected(SocketException exception) {
		return exception.getMessage().toLowerCase().contains("socket closed");
	}
	
	static boolean compareMimeTypes(String one, String two) {
		if(one.equals("*/*") || two.equals("*/*")) return true;
		String[] oneComponents = one.split("/");
		String[] twoComponents = two.split("/");
		if(oneComponents[1].equals("*") || twoComponents[1].equals("*")) return oneComponents[0].equals(twoComponents[0]);
		return one.equals(two);
	}
	
	static String exceptionToString(Throwable exception) {
		StringWriter sw = new StringWriter();
		PrintWriter pw = new PrintWriter(sw);
		exception.printStackTrace(pw);
		return exception.getMessage() + ":\n" + sw.toString();
	}
	
	public static class Tuple<A, B> {
		public final A item1;
		public final B item2;
		
		public Tuple(A item1, B item2) {
			this.item1 = item1;
			this.item2 = item2;
		}
	}
}