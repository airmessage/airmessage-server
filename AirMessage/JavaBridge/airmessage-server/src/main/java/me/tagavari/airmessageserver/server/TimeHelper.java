package me.tagavari.airmessageserver.server;

import java.util.Calendar;
import java.util.TimeZone;

public enum TimeHelper {
	COCOA_CORE_DATA, //Cocoa core data / Seconds since January 1st, 2001, 00:00, UTC-0
	MAC_ABSOLUTE_TIME; //Mac absolute time / Nanoseconds since January 1st, 2001, 00:00, UTC-0
	
	//Creating the reference variables
	private static final long millisAppleUnixDifference;
	
	static {
		//Initializing the variables
		millisAppleUnixDifference = getMillisAppleUnixDifference();
	}
	
	static TimeHelper getCorrectTimeSystem() {
		//Checking if the system version is earlier than macOS High Sierra
		if(Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSHighSierraVersion) < 0) return COCOA_CORE_DATA;
		else return MAC_ABSOLUTE_TIME;
	}
	
	public long toDatabaseTime(long time) {
		switch(this) {
			case COCOA_CORE_DATA:
				return (time - millisAppleUnixDifference) / 1000L; //Unix epoch -> Apple epoch / Milliseconds -> Seconds
			case MAC_ABSOLUTE_TIME:
				return (time - millisAppleUnixDifference) * 1000000L; //Unix epoch -> Apple epoch / Milliseconds -> Nanoseconds
			default:
				//Throwing an illegal state exception
				throw new IllegalStateException();
		}
	}
	
	long toUnixTime(long time) {
		//Calculating the time
		switch(this) {
			case COCOA_CORE_DATA:
				return time * 1000L + millisAppleUnixDifference; //Seconds -> Milliseconds / Apple epoch -> Unix epoch
			case MAC_ABSOLUTE_TIME:
				return time / 1000000L + millisAppleUnixDifference; //Nanoseconds -> Milliseconds / Apple epoch -> Unix epoch
			default:
				//Throwing an illegal state exception
				throw new IllegalStateException();
		}
	}
	
	static long getMillisSinceAppleEpoch() {
		Calendar calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"));
		calendar.clear();
		calendar.set(2001, Calendar.JANUARY, 1);
		return (System.currentTimeMillis() - calendar.getTimeInMillis());
	}
	
	static long getMillisAppleUnixDifference() {
		Calendar calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC"));
		calendar.clear();
		calendar.set(2001, Calendar.JANUARY, 1);
		long appleEpoch = calendar.getTimeInMillis();
		calendar.clear();
		calendar.set(1970, Calendar.JANUARY, 1);
		long unixEpoch = calendar.getTimeInMillis();
		
		return appleEpoch - unixEpoch;
	}
}