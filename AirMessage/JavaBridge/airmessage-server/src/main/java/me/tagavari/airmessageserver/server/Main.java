package me.tagavari.airmessageserver.server;

import me.tagavari.airmessageserver.connection.ConnectionManager;
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
	private static final File logFile = new File(Constants.applicationSupportDir, "logs/latest.log");
	public static final int databaseScanFrequency = 2 * 1000;
	private static final BlockingQueue<Runnable> runQueue = new LinkedBlockingQueue<>();
	
	//Creating the variables
	private static boolean debugMode = false;
	private static TimeHelper timeHelper;
	private static Logger logger;
	private static String deviceName;
	
	private static boolean isSetupMode;
	private static ServerState serverState = ServerState.SETUP;
	
	public static void main(String[] args) throws IOException {
		//Configuring the logger
		logger = Logger.getGlobal();
		logger.setLevel(Level.FINEST);
		if(!logFile.getParentFile().exists()) logFile.getParentFile().mkdir();
		else if(logFile.exists()) Files.move(logFile.toPath(), Constants.findFreeFile(logFile.getParentFile(), new SimpleDateFormat("YYYY-MM-dd").format(new Date()) + ".log", "-", 1).toPath());
		
		for(Handler handler : logger.getParent().getHandlers()) logger.getParent().removeHandler(handler);
		
		{
			FileHandler handler = new FileHandler(logFile.getPath());
			handler.setLevel(Level.FINEST);
			handler.setFormatter(getLoggerFormatter());
			logger.addHandler(handler);
		}
		
		{
			ConsoleHandler handler = new ConsoleHandler();
			handler.setLevel(Level.FINEST);
			handler.setFormatter(getLoggerFormatter());
			logger.addHandler(handler);
		}
		
		//Reading the device name
		deviceName = readDeviceName();
		
		if(isDebugMode()) {
			getLogger().log(Level.INFO, "Server running in debug mode");
		}
		
		//Logging the startup messages
		getLogger().info("Starting AirMessage Server version " + Constants.SERVER_VERSION);
		
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
		
		//Starting the main thread loop
		/* try {
			while(true) {
				runQueue.take().run();
			}
		} catch(InterruptedException exception) {
			exception.printStackTrace();
		} */
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
		ConnectionManager.assignDataProxy();
		
		//Updating the server state
		setServerState(ServerState.STARTING);
		
		//Loading the credentials
		//result = SecurityManager.loadCredentials();
		//if(!result) System.exit(1);
		
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
	
	private static Formatter getLoggerFormatter() {
		return new Formatter() {
			private final DateFormat dateFormat = new SimpleDateFormat("yy-MM-dd HH:mm:ss");
			
			@Override
			public String format(LogRecord record) {
				String stackTrace = "";
				if(record.getThrown() != null) {
					StringWriter errors = new StringWriter();
					record.getThrown().printStackTrace(new PrintWriter(errors));
					stackTrace = errors.toString();
				}
				return dateFormat.format(record.getMillis()) + ' ' + '[' + record.getLevel().toString() + ']' + ' ' + formatMessage(record) + '\n' + stackTrace;
			}
		};
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
	
	public static boolean isSetupMode() {
		return isSetupMode;
	}
	
	public static void setSetupMode(boolean isSetupMode) {
		Main.isSetupMode = isSetupMode;
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