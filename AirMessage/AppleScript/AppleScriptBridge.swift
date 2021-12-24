//
//  AppleScriptBridge.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import AppKit
import Carbon

class AppleScriptBridge {
	enum ScriptSourceCategory: String {
		case common = "Common"
		case messages = "Messages"
		case faceTime = "FaceTime"
	}
	
	private static func getScript(_ name: String, ofCategory category: ScriptSourceCategory) -> NSAppleScript {
		NSAppleScript.init(
			contentsOf: Bundle.main.url(forResource: name, withExtension: "applescript", subdirectory: "AppleScriptSource/\(category.rawValue)")!,
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
	
	private init() {
	}
	
	public static let shared = AppleScriptBridge()
	
	//MARK: - Common
	
	private lazy var scriptCommonPressCommandReturn = AppleScriptBridge.getScript("pressCommandReturn", ofCategory: .common)
	
	///Returns whether the app has permission to control System Events / Automation
	func checkPermissionsAutomation() -> Bool {
		let scriptTestAutomation = AppleScriptBridge.getScript("testPermissionsAutomation", ofCategory: .common)
		
		var scriptError: NSDictionary?
		scriptTestAutomation.executeAndReturnError(&scriptError)
		if let error = scriptError {
			LogManager.log("System Events permissions test failed: \(error)", level: .debug)
		}
		return scriptError == nil
	}
	
	func pressCommandReturn() throws {
		var scriptError: NSDictionary?
		scriptCommonPressCommandReturn.executeAndReturnError(&scriptError)
		if let error = scriptError {
			LogManager.log("Failed to press command-return: \(error)", level: .debug)
			throw AppleScriptExecutionError(error: error)
		}
	}
	
	//MARK: - Messages
	
	private lazy var scriptMessagesCreateChat = AppleScriptBridge.getScript("createChat", ofCategory: .messages)
	private lazy var scriptMessagesSendMessageExisting = AppleScriptBridge.getScript("sendMessageExisting", ofCategory: .messages)
	private lazy var scriptMessagesSendMessageDirect = AppleScriptBridge.getScript("sendMessageDirect", ofCategory: .messages)
	private lazy var scriptMessagesSendMessageNew = AppleScriptBridge.getScript("sendMessageNew", ofCategory: .messages)
	
	/**
	Returns if the app has permission to control Messages
	*/
	func checkPermissionsMessages() -> Bool {
		let scriptTestAutomation = AppleScriptBridge.getScript("testPermissionsMessages", ofCategory: .messages)
		
		var scriptError: NSDictionary?
		scriptTestAutomation.executeAndReturnError(&scriptError)
		if let error = scriptError {
			LogManager.log("Messages permissions test failed: \(error)", level: .debug)
		}
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
		let result = AppleScriptBridge.runScript(scriptMessagesCreateChat, params: params, error: &executeError)
		if let error = executeError {
			LogManager.log("Failed to create chat with \(addresses): \(error)", level: .error)
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
		AppleScriptBridge.runScript(scriptMessagesSendMessageExisting, params: params, error: &executeError)
		if let error = executeError {
			LogManager.log("Failed to send message to chat \(chatID): \(error)", level: .error)
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
		AppleScriptBridge.runScript(scriptMessagesSendMessageDirect, params: params, error: &executeError)
		if let error = executeError {
			LogManager.log("Failed to send direct message to \(address): \(error)", level: .error)
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
		AppleScriptBridge.runScript(scriptMessagesSendMessageNew, params: params, error: &executeError)
		if let error = executeError {
			LogManager.log("Failed to send message to new chat \(addresses): \(error)", level: .error)
			throw AppleScriptExecutionError(error: error)
		}
	}
	
	//MARK: - FaceTime
	
	private lazy var scriptFaceTimeCreateNewLink = AppleScriptBridge.getScript("getNewLink", ofCategory: .faceTime)
	private lazy var scriptFaceTimeGetActiveLink = AppleScriptBridge.getScript("getActiveLink", ofCategory: .faceTime)
	private lazy var scriptFaceTimeLeaveCall = AppleScriptBridge.getScript("leaveCall", ofCategory: .faceTime)
	private lazy var scriptFaceTimeAcceptPendingUser = AppleScriptBridge.getScript("acceptPendingUser", ofCategory: .faceTime)
	private lazy var scriptFaceTimeCenterWindow = AppleScriptBridge.getScript("centerWindow", ofCategory: .faceTime)
	
	private lazy var scriptFaceTimeQueryIncomingCall = AppleScriptBridge.getScript("queryIncomingCall", ofCategory: .faceTime)
	private lazy var scriptFaceTimeHandleIncomingCall = AppleScriptBridge.getScript("handleIncomingCall", ofCategory: .faceTime)
	private lazy var scriptFaceTimeInitiateOutgoingCall = AppleScriptBridge.getScript("initiateOutgoingCall", ofCategory: .faceTime)
	private lazy var scriptFaceTimeQueryOutgoingCall = AppleScriptBridge.getScript("queryOutgoingCall", ofCategory: .faceTime)
	
	enum OutgoingCallStatus: String {
		case pending = "pending"
		case accepted = "accepted"
		case rejected = "rejected"
	}
	
	///Creates and gets a new FaceTime link
	func getNewFaceTimeLink() throws -> String {
		var executeError: NSDictionary? = nil
		let result = scriptFaceTimeCreateNewLink.executeAndReturnError(&executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.stringValue!
		}
	}
	
	///Gets a FaceTime link for the active call
	func getActiveFaceTimeLink() throws -> String {
		var executeError: NSDictionary? = nil
		let result = scriptFaceTimeGetActiveLink.executeAndReturnError(&executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.stringValue!
		}
	}
	
	///Leaves the active FaceTime call
	func leaveFaceTimeCall() throws {
		var executeError: NSDictionary? = nil
		scriptFaceTimeLeaveCall.executeAndReturnError(&executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		}
	}
	
	///Accepts the first pending user for the current FaceTime call if present, returns false if there was no user to accept
	func acceptFaceTimeEntry() throws -> Bool {
		var executeError: NSDictionary? = nil
		let result = scriptFaceTimeAcceptPendingUser.executeAndReturnError(&executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.booleanValue
		}
	}
	
	///Centers the FaceTime window and the mouse cursor in the middle of the screen
	func centerFaceTimeWindow() throws {
		//Get the middle of the screen
		let screen = NSScreen.main!
		let rect = screen.frame
		let moveX = rect.size.width / 2
		let moveY = rect.size.height / 2
		
		let params = NSAppleEventDescriptor.list()
		params.insert(NSAppleEventDescriptor(int32: Int32(moveX)), at: 1)
		params.insert(NSAppleEventDescriptor(int32: Int32(moveY)), at: 2)
		
		var executeError: NSDictionary? = nil
		AppleScriptBridge.runScript(scriptFaceTimeCenterWindow, params: params, error: &executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		}
		
		//Move the cursor to the middle of the screen
		CGDisplayMoveCursorToPoint(0, CGPoint(x: moveX, y: moveY))
	}
	
	///Checks for incoming calls, returning the current caller name, or nil if there is no incoming call
	func queryIncomingCall() throws -> String? {
		var executeError: NSDictionary? = nil
		let result = scriptFaceTimeQueryIncomingCall.executeAndReturnError(&executeError)
		
		if let error = executeError {
			let appleScriptError = AppleScriptExecutionError(error: error)
			//Ignore error -1719 (invalid index) errors, as these can be caused by changing UI while the script is executing
			if appleScriptError.code != -1719 {
				throw appleScriptError
			} else {
				return nil
			}
		} else {
			let callerName = result.stringValue!.trimmingCharacters(in: .whitespacesAndNewlines)
			//The script returns an empty string if there is no incoming call
			if callerName.isEmpty {
				return nil
			} else {
				return callerName
			}
		}
	}
	
	///Accepts or rejects the current incoming call
	func handleIncomingCall(accept: Bool) throws -> Bool {
		let params = NSAppleEventDescriptor.list()
		params.insert(NSAppleEventDescriptor(boolean: accept), at: 1)
		
		var executeError: NSDictionary? = nil
		let result = AppleScriptBridge.runScript(scriptFaceTimeHandleIncomingCall, params: params, error: &executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.booleanValue
		}
	}
	
	///Creates and starts a new outgoing FaceTime call. Returns whether the call was created successfully.
	func initiateOutgoingCall(with addresses: [String]) throws -> Bool {
		let params = NSAppleEventDescriptor.list()
		params.insert(AppleScriptBridge.stringArrayToEventDescriptor(addresses), at: 1)
		
		var executeError: NSDictionary? = nil
		let result = AppleScriptBridge.runScript(scriptFaceTimeInitiateOutgoingCall, params: params, error: &executeError)
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return result.booleanValue
		}
	}
	
	///Checks the status of an outgoing call
	func queryOutgoingCall() throws -> OutgoingCallStatus {
		var executeError: NSDictionary? = nil
		let result = scriptFaceTimeQueryOutgoingCall.executeAndReturnError(&executeError)
		
		if let error = executeError {
			throw AppleScriptExecutionError(error: error)
		} else {
			return OutgoingCallStatus(rawValue: result.stringValue!)!
		}
	}
}
