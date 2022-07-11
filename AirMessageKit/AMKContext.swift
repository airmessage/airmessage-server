//
//  AMKContext.swift
//  AirMessageKit
//
//  Created by Cole Feuer on 2022-07-11.
//

import Foundation
import AirMessageKitIPC

public class AMKContext {
	private let launcher = MessagesLauncher()
	private let ipcBridge = AMIPCBridge()
	
	public init() {
		ipcBridge.delegate = self
	}
	
	///Gets whether the Messages process is running
	public var isRunning: Bool {
		launcher.isRunning
	}
	
	///Launches a new Messages process
	public func launch() {
		//Pass the launcher our Mach server port
		try! launcher.launch(machPort: ipcBridge.localPort.machPort)
	}
	
	///Cancels an existing Messages process
	public func terminate() {
		launcher.terminate()
	}
	
	public func sendMessage(_ message: String, toChat chat: String) throws {
		try ipcBridge.send(message: AMIPCMessage(withPayload: .sendMessage(message: message, chat: chat)))
	}
}

extension AMKContext: AMIPCBridgeDelegate {
	public func bridgeDelegate(onReceiveRegister port: UInt32) {
		print("Client connected under port \(port)")
		
		//Agent is ready, we can start sending messages
		try! sendMessage("Hey", toChat: "r")
	}
	
	public func bridgeDelegate(onReceive message: AMIPCMessage) {
		print("Received client message \(message)")
	}
}
