//
//  MessageManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

import Foundation

class MessageManager: NSObject {
	@objc class func createChat(withAddresses addresses: [String], service: String) throws -> String {
		if #available(macOS 11.0, *) {
			//Not supported
			throw AppleScriptSupportError(noSupportVer: "11.0")
		} else {
			return try AppleScriptBridge.shared.createChat(withAddresses: addresses, service: service)
		}
	}
	
	@objc class func send(message: String, toExistingChat chatID: String) throws {
		return try AppleScriptBridge.shared.sendMessage(toExistingChat: chatID, message: message, isFile: false)
	}
	
	@objc class func send(file: URL, toExistingChat chatID: String) throws {
		return try AppleScriptBridge.shared.sendMessage(toExistingChat: chatID, message: file.path, isFile: true)
	}
	
	@objc class func send(message: String, toNewChat addresses: [String], onService service: String) throws {
		//If there's only one member and we're on macOS 11, use our hacky workaround
		if #available(macOS 11.0, *) {
			if addresses.count == 1 {
				return try AppleScriptBridge.shared.sendMessage(toDirect: addresses[0], service: service, message: message, isFile: false)
			} else {
				throw AppleScriptSupportError(noSupportVer: "11.0")
			}
		} else {
			return try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: message, isFile: false)
		}
	}
	
	@objc class func send(file: URL, toNewChat addresses: [String], onService service: String) throws {
		//If there's only one member and we're on macOS 11, use our hacky workaround
		if #available(macOS 11.0, *) {
			if addresses.count == 1 {
				return try AppleScriptBridge.shared.sendMessage(toDirect: addresses[0], service: service, message: file.path, isFile: true)
			} else {
				throw AppleScriptSupportError(noSupportVer: "11.0")
			}
		} else {
			return try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: file.path, isFile: true)
		}
	}
}
