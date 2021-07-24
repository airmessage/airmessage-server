package me.tagavari.airmessageserver.server;

import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.connection.connect.DataProxyConnect;
import me.tagavari.airmessageserver.connection.direct.DataProxyTCP;
import me.tagavari.airmessageserver.constants.AccountType;
import me.tagavari.airmessageserver.jni.JNILogging;
import me.tagavari.airmessageserver.jni.JNIPreferences;
import me.tagavari.airmessageserver.jni.JNIUserInterface;

import java.io.*;
import java.nio.file.Files;
import java.security.SecureRandom;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.ResourceBundle;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.logging.*;
import java.util.stream.Collectors;

public class Main {
	//Creating the constants
	private static final SecureRandom secureRandom = new SecureRandom();
	public static final int databaseScanFrequency = 2 * 1000;
	
	//Creating the variables
	private static boolean debugMode = false;
	private static TimeHelper timeHelper;
	private static Logger logger;
	private static String deviceName;
	
	private static volatile ServerState serverState = ServerState.SETUP;
	
	public static void main(String[] args) throws IOException {
		//Configuring the logger
		logger = Logger.getGlobal();
		logger.setLevel(Level.FINEST);
		for(var handler : logger.getHandlers()) logger.removeHandler(handler);
		for(var handler : logger.getParent().getHandlers()) logger.getParent().removeHandler(handler);
		logger.addHandler(new Handler() {
			@Override
			public void publish(LogRecord record) {
				LogType logType;
				int levelValue = record.getLevel().intValue();
				if(levelValue <= Level.FINE.intValue()) logType = LogType.DEBUG;
				else if(levelValue <= Level.INFO.intValue()) logType = LogType.INFO;
				else if(levelValue <= Level.WARNING.intValue()) logType = LogType.NOTICE;
				else logType = LogType.ERROR;
				
				JNILogging.log(logType.code, record.getMessage());
			}
			
			@Override
			public void flush() {}
			
			@Override
			public void close() throws SecurityException {}
		});
		
		//Reading the device name
		deviceName = readDeviceName();
		
		if(isDebugMode()) {
			getLogger().info("Server running in debug mode");
		}
		
		//Initializing properties
		PropertiesManager.initializeProperties();
		
		//Getting the time system
		timeHelper = TimeHelper.getCorrectTimeSystem();
		getLogger().info("Using time system " + Main.getTimeHelper().toString() + " with current time " + System.currentTimeMillis() + " -> " + Main.getTimeHelper().toDatabaseTime(System.currentTimeMillis()));
		
		//Hiding JOOQ's splash
		System.setProperty("org.jooq.no-logo", "true");
		
		//Adding a shutdown hook
		Runtime.getRuntime().addShutdownHook(new Thread(() -> {
			//Stopping the services
			ConnectionManager.stop();
			DatabaseManager.stop();
			
			//Deleting the uploads directory
			Constants.recursiveDelete(Constants.uploadDir);
		}));
	}
	
	/**
	 * Runs the provided runnable on the main thread
	 */
	public static void postMainThread(Runnable runnable) {
		//runQueue.add(runnable);
		runnable.run();
	}
	
	/**
	 * Starts the server
	 */
	public static void startServer() {
		//Disconnecting the server if it's currently running
		ConnectionManager.stop();
		
		//Setting the data proxy
		int accountType = JNIPreferences.getAccountType();
		if(accountType == AccountType.accountTypeConnect) {
			ConnectionManager.setDataProxy(new DataProxyConnect(JNIPreferences.getInstallationID()));
		} else if(accountType == AccountType.accountTypeDirect) {
			ConnectionManager.setDataProxy(new DataProxyTCP(JNIPreferences.getServerPort()));
		}
		
		//Updating the server state
		setServerState(ServerState.STARTING);
		
		//Starting the database scanner
		if(DatabaseManager.getInstance() == null) {
			boolean result = DatabaseManager.start(databaseScanFrequency);
			if(!result) {
				//Updating the server state
				setServerState(ServerState.ERROR_DATABASE);
				
				//Returning
				return;
			}
		}
		
		//Starting the server manager
		ConnectionManager.start();
		
		//Logging a message
		getLogger().info("Initialization complete");
	}
	
	private static void processArgs(String[] args) {
		//Iterating over the arguments
		for(String argument : args) {
			//Debug
			if("-debug".equals(argument)) debugMode = true;
		}
	}
	
	public static boolean isDebugMode() {
		return debugMode;
	}
	
	public static TimeHelper getTimeHelper() {
		return timeHelper;
	}
	
	public static Logger getLogger() {
		return logger;
	}
	
	public static SecureRandom getSecureRandom() {
		return secureRandom;
	}
	
	public static ServerState getServerState() {
		return serverState;
	}
	
	public static void setServerState(ServerState value) {
		serverState = value;
		JNIUserInterface.updateUIState(value.code);
	}
	
	private static String readDeviceName() {
		try {
			Process process = Runtime.getRuntime().exec(new String[]{"scutil", "--get", "ComputerName"});
			
			if(process.waitFor() == 0) {
				//Reading and returning the input
				BufferedReader in = new BufferedReader(new InputStreamReader(process.getInputStream()));
				return in.lines().collect(Collectors.joining());
			} else {
				//Logging the error
				try(BufferedReader in = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
					String errorOutput = in.lines().collect(Collectors.joining());
					Main.getLogger().log(Level.WARNING, "Unable to read device name: " + errorOutput);
				}
			}
		} catch(IOException | InterruptedException exception) {
			//Printing the stack trace
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
		
		return null;
	}
	
	public static String getDeviceName() {
		return deviceName;
	}
}