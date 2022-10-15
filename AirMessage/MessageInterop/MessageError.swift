//
//  MessageError.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-20.
//

import Foundation

/**
 An error that represents an AppleScript execution error
 */
struct AppleScriptError: Error, LocalizedError, CustomNSError {
	let errorDict: [String: Any]
	let fileURL: URL?
	init(error: NSDictionary, fileURL: URL? = nil) {
		errorDict = error as! [String: Any]
		self.fileURL = fileURL
	}
	
	var code: Int {
		(errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
	}
	var message: String {
		(errorDict[NSAppleScript.errorMessage] as? String) ?? "AppleScript execution error"
	}
	
	//LocalizedError
	
	var errorDescription: String? {
		if let fileURL = fileURL {
			return "AppleScript error \(code) for file \(fileURL): \(message)"
		} else {
			return "AppleScript error \(code): \(message)"
		}
	}
	
	//CustomNSError
	
	static let errorDomain = "AppleScriptErrorDomain"
	var errorCode: Int { code }
	var errorUserInfo: [String: Any] { errorDict }
}

///An error that represents a failure to load an AppleScript file
struct AppleScriptInitializationError: Error, LocalizedError {
	let fileURL: URL
	init(fileURL: URL) {
		self.fileURL = fileURL
	}
	
	public var errorDescription: String? {
		"Failed to load AppleScript file \(fileURL)"
	}
}

/**
 An error that represents when functionality isn't available on a newer version of macOS
 */
struct ForwardsSupportError: Error, LocalizedError {
	let noSupportVer: String
	init(noSupportVer: String) {
		self.noSupportVer = noSupportVer
	}
	
	public var errorDescription: String? {
		"Not supported beyond macOS \(noSupportVer) (running \(ProcessInfo.processInfo.operatingSystemVersionString))"
	}
}
