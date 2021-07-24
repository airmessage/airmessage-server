//
//  LogHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

import Foundation
import os

private let standardDateFormatter: DateFormatter = {
	let dateFormatter = DateFormatter()
	dateFormatter.locale = Locale(identifier: "en_US_POSIX")
	dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
	return dateFormatter
}()

private struct FileLogger: TextOutputStream {
	var file: URL
	
	func write(_ string: String) {
		let data = string.data(using: .utf8)!
		
		if let fileHandle = FileHandle(forWritingAtPath: file.path) {
			defer {
				fileHandle.closeFile()
			}
			fileHandle.seekToEndOfFile()
			fileHandle.write(data)
		} else {
			try! data.write(to: file, options: .atomic)
		}
	}
}

class LogManager: NSObject {
	private var fileLogger: FileLogger
	
	@available(macOS 10.12, *)
	private lazy var osLogMain = OSLog.init(subsystem: Bundle.main.bundleIdentifier!, category: "main")
	@available(macOS 10.12, *)
	private lazy var osLogJava = OSLog.init(subsystem: Bundle.main.bundleIdentifier!, category: "java")
	
	@objc public static let shared = LogManager()
	
	private override init() {
		//Use file logger
		fileLogger = FileLogger(file: LogManager.prepareLogFile())
	}
	
	@available(macOS 10.12, *)
	private static func mapLogTypeOS(_ type: LogType) -> OSLogType {
		switch type {
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
	
	private static func mapLogTypeDisplay(_ type: LogType) -> String {
		switch type {
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
	
	private static func prepareLogFile() -> URL {
		//Create the log directory
		let logDirectory = StorageManager.storageDirectory.appendingPathComponent("logs", isDirectory: true)
		
		if !FileManager.default.fileExists(atPath: logDirectory.path) {
			try! FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: false, attributes: nil)
		}
		
		//Moving the log file
		let logFile = logDirectory.appendingPathComponent("latest.log", isDirectory: false)
		if FileManager.default.fileExists(atPath: logFile.path) {
			let dateFormatter = DateFormatter()
			dateFormatter.locale = Locale(identifier: "en_US_POSIX")
			dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
			
			let targetFileName = dateFormatter.string(from: Date()) + ".log"
			let targetFile = logDirectory.appendingPathComponent(targetFileName, isDirectory: false)
			
			try! FileManager.default.moveItem(at: logFile, to: targetFile)
		}
		
		return logFile
	}
	
	public func log(_ message: StaticString, type: LogType, _ args: CVarArg...) {
		let typeLabel = LogManager.mapLogTypeDisplay(type)
		let timestamp = standardDateFormatter.string(from: Date())
		
		//Log to file
		let stringMessage = message.withUTF8Buffer {
			String(decoding: $0, as: UTF8.self)
		}
		fileLogger.write("\(timestamp) [\(typeLabel)] \(String(format: stringMessage, arguments: args))\n")
		
		if #available(macOS 10.12, *) {
			//Log to os_log
			let osLogType = LogManager.mapLogTypeOS(type)
			
			switch args.count {
				case 1:
					os_log(message, log: osLogMain, type: osLogType, args[0])
				case 2:
					os_log(message, log: osLogMain, type: osLogType, args[0], args[1])
				case 3:
					os_log(message, log: osLogMain, type: osLogType, args[0], args[1], args[2])
				default:
					os_log(message, log: osLogMain, type: osLogType)
			}
		} else {
			//Log to standard output
			let typePrefix = "[\(typeLabel)] "
			switch args.count {
				case 1:
					NSLog(typePrefix + stringMessage, args[0])
				case 2:
					NSLog(typePrefix + stringMessage, args[0], args[1])
				case 3:
					NSLog(typePrefix + stringMessage, args[0], args[1], args[2])
				default:
					NSLog(typePrefix + stringMessage)
			}
		}
	}
	
	@objc public func javaLog(_ message: String, type: LogType) {
		let typeLabel = LogManager.mapLogTypeDisplay(type)
		let timestamp = standardDateFormatter.string(from: Date())
		
		//Log to file
		fileLogger.write("\(timestamp) [java] [\(typeLabel)] \(message)\n")
		
		//Log to os_log
		if #available(macOS 10.12, *) {
			let osLogType = LogManager.mapLogTypeOS(type)
			
			os_log("%@", log: osLogJava, type: osLogType, message)
		} else {
			//Log to standard output
			NSLog("[java] [\(typeLabel)] \(message)")
		}
	}
}

@objc enum LogType: Int {
	case debug = 0
	case info = 1
	case notice = 2
	case error = 3
	case fault = 4
}
