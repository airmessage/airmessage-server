//
//  LogHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

import Foundation
import os

enum LogLevel {
	case debug
	case info
	case notice
	case error
	case fault
	
	/**
	 Gets this log level as a display string
	 */
	var label: String {
		switch self {
			case .debug:
				return "debug"
			case .info:
				return "info"
			case .notice:
				return "notice"
			case .error:
				return "error"
			case .fault:
				return "fault"
		}
	}
	
	/**
	 Gets this log level as an `OSLogType`
	 */
	@available(macOS 10.12, *)
	var osLogType: OSLogType {
		switch self {
			case .debug:
				return .debug
			case .info:
				return .info
			case .notice:
				return .default
			case .error:
				return .error
			case .fault:
				return .fault
		}
	}
}

private let standardDateFormatter: DateFormatter = {
	let dateFormatter = DateFormatter()
	dateFormatter.locale = Locale(identifier: "en_US_POSIX")
	dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
	return dateFormatter
}()

private struct FileLogger: TextOutputStream {
	var file: URL
	
	func write(_ string: String) {
		let fileHandle = try! FileHandle(forWritingTo: file)
		try! fileHandle.seekToEndCompat()
		try! fileHandle.writeCompat(contentsOf: string.data(using: .utf8)!)
	}
}

class LogManager {
	private static var fileLogger: FileLogger = {
		//Create the log directory
		let logDirectory = StorageManager.storageDirectory.appendingPathComponent("logs", isDirectory: true)
		if !FileManager.default.fileExists(atPath: logDirectory.path) {
			try! FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: false, attributes: nil)
		}
		
		//Move the previous log file
		let logFile = logDirectory.appendingPathComponent("latest.log", isDirectory: false)
		if FileManager.default.fileExists(atPath: logFile.path) {
			let dateFormatter = DateFormatter()
			dateFormatter.locale = Locale(identifier: "en_US_POSIX")
			dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
			
			let targetFileName = dateFormatter.string(from: Date()) + ".log"
			let targetFile = logDirectory.appendingPathComponent(targetFileName, isDirectory: false)
			
			try! FileManager.default.moveItem(at: logFile, to: targetFile)
		}
		
		guard FileManager.default.createFile(atPath: logFile.path, contents: nil) else {
			print("Failed to create log file at \(logFile.path), exiting")
			exit(0)
		}
		
		//Create the file logger
		return FileLogger(file: logFile)
	}()
	
	@available(macOS 11.0, *)
	private static var loggerMain = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "main")
	@available(macOS 10.12, *)
	private static var osLogMain = OSLog.init(subsystem: Bundle.main.bundleIdentifier!, category: "main")
	
	public static func log(_ message: String, level: LogLevel) {
		let timestamp = standardDateFormatter.string(from: Date())
		let typeLabel = level.label
		
		//Log to file
		fileLogger.write("\(timestamp) [\(typeLabel)] \(message)\n")
		
		if #available(macOS 11.0, *) {
			//Log to Logger
			loggerMain.log(level: level.osLogType, "\(message, privacy: .public)")
		} else if #available(macOS 10.12, *) {
			//Log to os_log
			os_log("%{public}@", log: osLogMain, type: level.osLogType, message)
		} else {
			//Log to standard output
			NSLog("[\(typeLabel)] \(message)")
		}
	}
}
