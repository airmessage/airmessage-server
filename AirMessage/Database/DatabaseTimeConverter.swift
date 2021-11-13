//
//  DatabaseManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-11.
//

import Foundation

private enum TimeSystem {
	case cocoaCoreData //Cocoa core data / Seconds since January 1st, 2001, 00:00, UTC-0
	case macAbsoluteTime //Mac absolute time / Nanoseconds since January 1st, 2001, 00:00, UTC-0
}

/*
 Mac Absolute Time is used in the Messages database on macOS 10.13 and above
 Earlier system versions use Cocoa Core Data
 */
private var system: TimeSystem {
	if #available(macOS 10.13, *) {
		return .macAbsoluteTime
	} else {
		return .cocoaCoreData
	}
}

//The difference (in milliseconds) between the Unix epoch (1970) and Apple epoch (2001)
private let appleUnixEpochDifference: Int64 = 978_307_200 * 1000

/**
 Gets the current time in database time
 */
func getDBTime() -> Int64 {
	if system == .macAbsoluteTime {
		//CoreFoundation time is in seconds, multiply to get nanoseconds
		return Int64(CFAbsoluteTimeGetCurrent() * 1e9)
	} else {
		return Int64(CFAbsoluteTimeGetCurrent())
	}
}

/**
 Converts from UNIX time to database time
 */
func convertDBTime(fromUNIX time: Int64) -> Int64 {
	if system == .macAbsoluteTime {
		return (time - appleUnixEpochDifference) * 1_000_000 //Unix epoch -> Apple epoch, milliseconds -> nanoseconds
	} else {
		return (time - appleUnixEpochDifference) / 1000 //Unix epoch -> Apple epoch / milliseconds -> seconds
	}
}

/**
 Converts from database time to UNIX time
 */
func convertDBTime(fromDB time: Int64) -> Int64 {
	if system == .macAbsoluteTime {
		return time / 1_000_000 + appleUnixEpochDifference; //Nanoseconds -> milliseconds / Apple epoch -> Unix epoch
	} else {
		return time * 1000 + appleUnixEpochDifference; //Seconds -> milliseconds / Apple epoch -> Unix epoch
	}
}