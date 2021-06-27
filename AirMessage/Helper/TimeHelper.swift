import Foundation

//Milliseconds difference between Apple epoch (2001-01-01) and Unix epoch (1970-01-01)
private let millisDifference: Int64 = 978307200000

//Convert from Unix time to database time
func toDatabaseTime(_ time: Int64) -> Int64 {
	if #available(macOS 10.13, *) {
		//Use Mac absolute time
		return (time - millisDifference) * 1000000 //Unix epoch -> Apple epoch, milliseconds -> nanoseconds
	} else {
		//Use Cocoa core data
		return (time - millisDifference) / 1000 //Unix epoch -> Apple epoch, milliseconds -> seconds
	}
}

//Convert from database time to Unix time
func toUnixTime(_ time: Int64) -> Int64 {
	if #available(macOS 10.13, *) {
		//Use Mac absolute time
		return time / 1000000 + millisDifference //nanoseconds -> milliseconds, Apple epoch -> Unix epoch
	} else {
		//Use Cocoa core data
		return time * 1000 + millisDifference //seconds -> milliseconds, Apple epoch -> Unix epoch
	}
}