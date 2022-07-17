//
//  Agent.swift
//  AirMessageKitAgent
//
//  Created by Cole Feuer on 2022-07-09.
//

import Foundation
import IMCore11
import AirMessageKitIPC

class Agent: NSObject {
	private(set) static var sharedInstance: Agent!
	
	private(set) var ipcBridge: AMIPCBridge!
	
	@objc func startAgent() {
		print("Starting AirMessageKit agent")
		
		//Make sure we were injected
		guard ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil else {
			try! FileHandle.standardError.write(contentsOf: Data("Not injected with DYLD_INSERT_LIBRARIES, exiting".utf8))
			return
		}
		
		//Get the pipe directory to connect to
		guard let sockFileRaw = ProcessInfo.processInfo.environment["AIRMESSAGEKIT_SOCK_FILE"] else {
			try! FileHandle.standardError.write(contentsOf: Data("AIRMESSAGEKIT_SOCK_FILE is not available, exiting".utf8))
			return
		}
		
		//Set the shared agent
		Agent.sharedInstance = self
		
		//Initialize IPC
		ipcBridge = AMIPCBridge(withSocketFile: URL(fileURLWithPath: sockFileRaw))
		ipcBridge.delegate = self
		ipcBridge.connectClient()
	}
}

extension Agent: AMIPCBridgeDelegate {
	func bridgeDelegateOnConnect() {
		print("Agent is connected!")
		
		print("Send connected message...")
		ipcBridge.send(message: AMIPCMessage(withPayload: .connected)) { err in
			print("Sent connected message with result \(err)")
		}
	}
	
	func bridgeDelegate(onError error: Error) {
		print("Encountered bridge delegate error \(error)")
		print(Thread.callStackSymbols)
	}
	
	func bridgeDelegate(onReceive message: AMIPCMessage) {
		print("Received IPC message \(message)!")
	}
}
