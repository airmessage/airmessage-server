//
//  MessageManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

import Foundation
import AppKit

class MessageManager {
	static func createChat(withAddresses addresses: [String], service: String) throws -> String {
		if #available(macOS 11.0, *) {
			//Not supported
			throw ForwardsSupportError(noSupportVer: "11.0")
		} else {
			return try AppleScriptBridge.shared.createChat(withAddresses: addresses, service: service)
		}
	}
	
	static func send(message: String, toExistingChat chatID: String) throws {
		return try AppleScriptBridge.shared.sendMessage(toExistingChat: chatID, message: message, isFile: false)
	}
	
	static func send(file: URL, toExistingChat chatID: String) throws {
		return try AppleScriptBridge.shared.sendMessage(toExistingChat: chatID, message: file.path, isFile: true)
	}
	
	static func send(message: String, toNewChat addresses: [String], onService service: String) throws {
		//Use NSSharingService on macOS 11+
		if #available(macOS 11.0, *) {
			DispatchQueue.main.sync {
				//Open the sharing service
				let service = NSSharingService(named: NSSharingService.Name.composeMessage)!
				service.recipients = addresses
				service.perform(withItems: [message])
			}
			
			//Submit the sharing service
			Thread.sleep(forTimeInterval: 1)
			try AppleScriptBridge.shared.pressCommandReturn()
		} else {
			try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: message, isFile: false)
		}
	}
	
	static func send(file: URL, toNewChat addresses: [String], onService service: String) throws {
		//Use NSSharingService on macOS 11+
		if #available(macOS 11.0, *) {
			DispatchQueue.main.sync {
				//Open the sharing service
				let service = NSSharingService(named: NSSharingService.Name.composeMessage)!
				service.recipients = addresses
				service.perform(withItems: [file])
			}
			
			//Submit the sharing service
			Thread.sleep(forTimeInterval: 1)
			try AppleScriptBridge.shared.pressCommandReturn()
		} else {
			return try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: file.path, isFile: true)
		}
	}
}
