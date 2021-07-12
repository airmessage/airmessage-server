package me.tagavari.airmessageserver.connection;

import java.util.Arrays;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class ClientRegistration {
	/**
	 * The installation ID of this instance
	 * Used for blocking multiple connections from the same client
	 */
	private String installationID;
	
	/**
	 * A human-readable name for this client
	 * Used when displaying connected clients to the user
	 * Examples:
	 * - Samsung Galaxy S20
	 * - Firefox 75
	 */
	private String clientName;
	
	/**
	 * The ID of the platform this device is running on
	 * Examples:
	 * - "android" (AirMessage for Android)
	 * - "google chrome" (AirMessage for web)
	 * - "windows" (AirMessage on Electron)
	 */
	private String platformID;
	
	/**
	 * TRUE if this client has successfully authenticated and can
	 * access protected resources
	 */
	private boolean clientRegistered = false;
	
	/**
	 * The current awaited transmission check for this client
	 */
	private byte[] transmissionCheck;
	
	/**
	 * Keeps track of whether this client is connected or not
	 */
	private final AtomicBoolean isConnected = new AtomicBoolean(true);
	
	//Creating the timer values
	private Timer handshakeExpiryTimer;
	private Timer pingResponseTimer = new Timer();
	private final Lock pingResponseTimerLock = new ReentrantLock();
	
	public String getInstallationID() {
		return installationID;
	}
	
	public String getClientName() {
		return clientName;
	}
	
	public String getPlatformID() {
		return platformID;
	}
	
	public void setRegistration(String installationID, String clientName, String platformID) {
		this.installationID = installationID;
		this.clientName = clientName;
		this.platformID = platformID;
	}
	
	public boolean isClientRegistered() {
		return clientRegistered;
	}
	
	public void setClientRegistered(boolean clientRegistered) {
		this.clientRegistered = clientRegistered;
	}
	
	public void startHandshakeExpiryTimer(long timeout, Runnable runnable) {
		handshakeExpiryTimer = new Timer();
		handshakeExpiryTimer.schedule(new TimerTask() {
			@Override
			public void run() {
				//Invalidating the registration timer
				handshakeExpiryTimer = null;
				
				//Calling the runnable
				runnable.run();
			}
		}, timeout);
	}
	
	public void cancelHandshakeExpiryTimer() {
		handshakeExpiryTimer.cancel();
		handshakeExpiryTimer = null;
	}
	
	public void startPingExpiryTimer(long timeout, Runnable runnable) {
		pingResponseTimerLock.lock();
		try {
			if(pingResponseTimer == null) {
				pingResponseTimer = new Timer();
				pingResponseTimer.schedule(new TimerTask() {
					@Override
					public void run() {
						pingResponseTimerLock.lock();
						try {
							pingResponseTimer = null;
						} finally {
							pingResponseTimerLock.unlock();
						}
						
						runnable.run();
					}
				}, timeout);
			}
		} finally {
			pingResponseTimerLock.unlock();
		}
	}
	
	public void cancelPingExpiryTimer() {
		pingResponseTimerLock.lock();
		try {
			if(pingResponseTimer != null) {
				pingResponseTimer.cancel();
				pingResponseTimer = null;
			}
		} finally {
			pingResponseTimerLock.unlock();
		}
	}
	
	public void cancelAllTimers() {
		//Cancelling the handshake expiry timer
		if(handshakeExpiryTimer != null) {
			handshakeExpiryTimer.cancel();
			handshakeExpiryTimer = null;
		}
		
		//Cancelling the ping response timer
		pingResponseTimerLock.lock();
		try {
			if(pingResponseTimer != null) {
				pingResponseTimer.cancel();
				pingResponseTimer = null;
			}
		} finally {
			pingResponseTimerLock.unlock();
		}
	}
	
	public void setTransmissionCheck(byte[] value) {
		transmissionCheck = value;
	}
	
	public boolean checkClearTransmissionCheck(byte[] value) {
		boolean result = Arrays.equals(transmissionCheck, value);
		transmissionCheck = null;
		return result;
	}
	
	public boolean isConnected() {
		return isConnected.get();
	}
	
	public void setConnected(boolean connected) {
		isConnected.set(connected);
	}
}