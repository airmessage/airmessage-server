package me.tagavari.airmessageserver.server;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

public class PropertiesManager {
	private static String connectEndpoint;
	
	public static void initializeProperties() throws IOException {
		Properties properties = new Properties();
		InputStream inputStream = Main.class.getClassLoader().getResourceAsStream("secrets.properties");
		
		properties.load(inputStream);
		
		connectEndpoint = properties.getProperty("connectEndpoint");
	}
	
	public static String getConnectEndpoint() {
		return connectEndpoint;
	}
}