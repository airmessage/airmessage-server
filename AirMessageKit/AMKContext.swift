//
//  AMKContext.swift
//  AirMessageKit
//
//  Created by Cole Feuer on 2022-07-11.
//

import Foundation
import AirMessageKitIPC

public class AMKContext {
	private var ipcBridge: AMIPCBridge
	private let sockFile: URL
	private let launcher = MessagesLauncher()
	
	public init() throws {
		print("Create temp dir")
		//Get a temporary file for the socket
		let temporaryDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		sockFile = temporaryDirectoryURL.appendingPathComponent("\(ProcessInfo().globallyUniqueString).sock")
		print("Created sock file at \(sockFile.path)")
		
		print("Init IPC bridge")
		//Initialize the IPC bridge
		ipcBridge = AMIPCBridge(withSocketFile: sockFile)
		ipcBridge.delegate = self
	}
	
	deinit {
		//Delete sock file
		try? FileManager.default.removeItem(at: sockFile)
	}
	
	///Gets whether the Messages process is running
	public var isRunning: Bool {
		launcher.isRunning
	}
	
	///Launches a new Messages process
	public func launch() {
		//Start listening
		ipcBridge.receiveClient()
		
		//Pass the launcher our pipe directory
		try! launcher.launch(withSockFile: sockFile)
	}
	
	///Cancels an existing Messages process
	public func terminate() {
		launcher.terminate()
	}
	
	public func sendMessage(_ message: String, toChat chat: String) {
		ipcBridge.send(message: AMIPCMessage(withPayload: .sendMessage(message: message, chat: chat)))
	}
}

extension AMKContext: AMIPCBridgeDelegate {
	public func bridgeDelegateOnConnect() {
		print("Bridge delegate connected!")
	}
	
	public func bridgeDelegate(onError error: Error) {
		print("Bridge delegate error: \(error)")
	}
	
	public func bridgeDelegate(onReceive message: AMIPCMessage) {
		print("Received client message \(message)")
	}
}
