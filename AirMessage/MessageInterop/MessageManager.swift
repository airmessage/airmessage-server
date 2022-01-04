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
			//NSSharingService only supports iMessage
			guard service == "iMessage" else {
				throw ForwardsSupportError(noSupportVer: "11.0")
			}
			
			DispatchQueue.main.sync {
				//Open the sharing service
				let service = NSSharingService(named: NSSharingService.Name.composeMessage)!
				service.delegate = autoSubmitNSSharingServiceDelegate
				service.recipients = addresses
				service.perform(withItems: [message])
			}
		} else {
			try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: message, isFile: false)
		}
	}
	
	static func send(file: URL, toNewChat addresses: [String], onService service: String) throws {
		//Use NSSharingService on macOS 11+
		if #available(macOS 11.0, *) {
			//NSSharingService only supports iMessage
			guard service == "iMessage" else {
				throw ForwardsSupportError(noSupportVer: "11.0")
			}
			
			DispatchQueue.main.sync {
				//Open the sharing service
				let service = NSSharingService(named: NSSharingService.Name.composeMessage)!
				service.delegate = autoSubmitNSSharingServiceDelegate
				service.recipients = addresses
				service.perform(withItems: [file])
			}
		} else {
			return try AppleScriptBridge.shared.sendMessage(toNewChat: addresses, service: service, message: file.path, isFile: true)
		}
	}
}

private let autoSubmitNSSharingServiceDelegate = AutoSubmitNSSharingServiceDelegate()

private class AutoSubmitNSSharingServiceDelegate: NSObject, NSSharingServiceDelegate {
	private var timer: Timer?
	
	private func startTimer() {
		//Ignore if the timer already exists
		guard timer == nil else { return }
		
		//Set a timer to try and submit every second
		timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(runSubmit), userInfo: nil, repeats: true)
	}
	
	private func stopTimer() {
		timer?.invalidate()
		timer = nil
	}
	
	func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
		startTimer()
		
	}
	
	func sharingService(_ sharingService: NSSharingService, didShareItems: [Any]) {
		stopTimer()
	}
	
	func sharingService(_ sharingService: NSSharingService, didFailToShareItems: [Any], error: Error) {
		stopTimer()
	}
	
	@objc private func runSubmit() {
		do {
			try AppleScriptBridge.shared.pressCommandReturn()
		} catch {
			stopTimer()
		}
	}
}
