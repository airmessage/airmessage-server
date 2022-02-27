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
struct AppleScriptExecutionError: Error, LocalizedError, CustomNSError {
	let errorDict: [String: Any]
	init(error: NSDictionary) {
		errorDict = error as! [String: Any]
	}
	
	var code: Int {
		(errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
	}
	var message: String {
		(errorDict[NSAppleScript.errorMessage] as? String) ?? "AppleScript execution error"
	}
	
	//LocalizedError
	
	var errorDescription: String? {
		"AppleScript error \(code): \(message)"
	}
	
	//CustomNSError
	
	static let errorDomain = "AppleScriptErrorDomain"
	var errorCode: Int { code }
	var errorUserInfo: [String: Any] { errorDict }
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
