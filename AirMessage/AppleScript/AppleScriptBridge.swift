//
//  AppleScriptBridge.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import Carbon

class AppleScriptBridge {
	private static func getScript(_ name: String) -> NSAppleScript {
		NSAppleScript.init(
			contentsOf: Bundle.main.url(forResource: name, withExtension: "applescript", subdirectory: "AppleScriptSource")!,
			error: nil)!
	}
	
	@discardableResult
	private static func runScript(_ script: NSAppleScript, params parameters: NSAppleEventDescriptor, error errorInfo: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) -> NSAppleEventDescriptor {
		var psn = ProcessSerialNumber(highLongOfPSN: UInt32(0), lowLongOfPSN: UInt32(kCurrentProcess))
		
		let target = NSAppleEventDescriptor(descriptorType: typeProcessSerialNumber, bytes: &psn, length: MemoryLayout<ProcessSerialNumber>.size)
		
		let handler = NSAppleEventDescriptor(string: "main")
		
		let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
		
		event.setParam(handler, forKeyword: AEKeyword(keyASSubroutineName))
		event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
		
		return script.executeAppleEvent(event, error: errorInfo)
	}
	
	private static func stringArrayToEventDescriptor(_ array: [String]) -> NSAppleEventDescriptor {
		let list = NSAppleEventDescriptor.list()
		for (index, entry) in array.enumerated() {
			list.insert(NSAppleEventDescriptor(string: entry), at: index + 1)
		}
		
		return list
	}
	
	private lazy var scriptCreateChat = AppleScriptBridge.getScript("createChat")
	private lazy var scriptSendMessageExisting = AppleScriptBridge.getScript("sendMessageExisting")
	private lazy var scriptSendMessageDirect = AppleScriptBridge.getScript("sendMessageDirect")
	private lazy var scriptSendMessageNew = AppleScriptBridge.getScript("sendMessageNew")
	
	private init() {
	}
	
	public static let shared = AppleScriptBridge()
	
	/**
	Returns if the app has permission to control Messages
	*/
	func checkPermissionsMessages() -> Bool {
		//Compile the script when this function is invoked, since this likely won't be called enough to be worth saving the compiled result for later
		let scriptTestAutomation = NSAppleScript.init(
				contentsOf: Bundle.main.url(forResource: "testPermissionsMessages", withExtension: "applescript", subdirectory: "AppleScriptSource")!,
				error: nil)!
		
		var scriptError: NSDictionary?
		scriptTestAutomation.executeAndReturnError(&scriptError)
		return scriptError == nil
	}
	
	/**
	Creates a chat, and returns its GUID
	*/
	func createChat(withAddresses addresses: [String], service: String) throws -> String {
		if #available(macOS 11.0, *) {
			//Not supported
			throw ForwardsSupportError(noSupportVer: "11.0")
		}
		
		let params = NSAppleEventDescriptor.list()
		params.insert(AppleScriptBridge.stringArrayToEventDescriptor(addresses), at: 1)
		params.insert(NSAppleEventDescriptor(string: service), at: 2)
		
		var executeError: NSDictionary? = nil
		let result = AppleScriptBridge.runScript(scriptCreateChat, params: params, error: &executeError)
		if let error = executeError {
			LogManager.shared.log("Failed to create chat with %@: %@", type: .error, addresses, error)
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.stringValue!
		}
	}
	
	/**
	Sends a message to an existing chat GUID
	*/
	func sendMessage(toExistingChat chatID: String, message: String, isFile: Bool) throws {
		let params = NSAppleEventDescriptor.list()
		params.insert(NSAppleEventDescriptor(string: chatID), at: 1)
		params.insert(NSAppleEventDescriptor(string: message), at: 2)
		params.insert(NSAppleEventDescriptor(boolean: isFile), at: 3)
		
		var executeError: NSDictionary? = nil
		AppleScriptBridge.runScript(scriptSendMessageExisting, params: params, error: &executeError)
		if let error = executeError {
			LogManager.shared.log("Failed to send message to chat %{public}: %{public}", type: .error, chatID, error)
			throw AppleScriptExecutionError(error: error)
		}
	}
	
	/**
	Sends a message to a single recipient
	*/
	func sendMessage(toDirect address: String, service: String, message: String, isFile: Bool) throws {
		let params = NSAppleEventDescriptor.list()
		params.insert(NSAppleEventDescriptor(string: address), at: 1)
		params.insert(NSAppleEventDescriptor(string: service), at: 2)
		params.insert(NSAppleEventDescriptor(string: message), at: 3)
		params.insert(NSAppleEventDescriptor(boolean: isFile), at: 4)
		
		var executeError: NSDictionary? = nil
		AppleScriptBridge.runScript(scriptSendMessageDirect, params: params, error: &executeError)
		if let error = executeError {
			LogManager.shared.log("Failed to send direct message to %{public}: %{public}", type: .error, message, error)
			throw AppleScriptExecutionError(error: error)
		}
	}
	
	/**
	Creates a new chat with a list of recipients, and sends a message to it
	*/
	func sendMessage(toNewChat addresses: [String], service: String, message: String, isFile: Bool) throws {
		if #available(macOS 11.0, *) {
			//Not supported
			throw ForwardsSupportError(noSupportVer: "11.0")
		}
		
		let params = NSAppleEventDescriptor.list()
		params.insert(AppleScriptBridge.stringArrayToEventDescriptor(addresses), at: 1)
		params.insert(NSAppleEventDescriptor(string: service), at: 2)
		params.insert(NSAppleEventDescriptor(string: message), at: 3)
		params.insert(NSAppleEventDescriptor(boolean: isFile), at: 4)
		
		var executeError: NSDictionary? = nil
		AppleScriptBridge.runScript(scriptSendMessageNew, params: params, error: &executeError)
		if let error = executeError {
			LogManager.shared.log("Failed to send message to new chat %{public}: %{public}", type: .error, addresses, error)
			throw AppleScriptExecutionError(error: error)
		}
	}
}
