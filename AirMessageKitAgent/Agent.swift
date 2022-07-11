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
		
		//Get the Mach port to connect to
		guard let machPortStr = ProcessInfo.processInfo.environment["AIRMESSAGEKIT_IPC_MACH"] else {
			try! FileHandle.standardError.write(contentsOf: Data("AIRMESSAGEKIT_IPC_MACH is not available, exiting".utf8))
			return
		}
		
		guard let machPortRaw = UInt32(machPortStr) else {
			try! FileHandle.standardError.write(contentsOf: Data("AIRMESSAGEKIT_IPC_MACH value \(machPortStr) is not valid, exiting".utf8))
			return
		}
		
		//Get the parent process id
		guard let parentTaskPortStr = ProcessInfo.processInfo.environment["AIRMESSAGEKIT_TASK_PORT"] else {
			try! FileHandle.standardError.write(contentsOf: Data("AIRMESSAGEKIT_TASK_PORT is not available, exiting".utf8))
			return
		}
		
		guard let parentTaskPort = mach_port_t(parentTaskPortStr) else {
			try! FileHandle.standardError.write(contentsOf: Data("AIRMESSAGEKIT_TASK_PORT value \(parentTaskPortStr) is not valid, exiting".utf8))
			return
		}
		
		print("Checking")
		
		//Set the shared agent
		Agent.sharedInstance = self
		
		print("Checking for ports under task port: \(parentTaskPort)")
		
		var ports: thread_act_array_t?
		var portsCount = mach_msg_type_number_t(0)
		guard mach_ports_lookup(parentTaskPort, &ports, &portsCount) == KERN_SUCCESS else {
			fatalError("Unable to lookup ports")
		}
		guard let port = ports?.pointee else {
			fatalError("Unable to get port")
		}
		print("Got port: \(port) (\(portsCount) results)")
		
		//Initialize IPC
		ipcBridge = AMIPCBridge(forRemotePort: NSMachPort(machPort: machPortRaw))
		ipcBridge.delegate = self
		
		//Send a registration message
		print("Send connected message...")
		try! ipcBridge.notifyRegistration()
		print("Sent connected message!")
	}
}

extension Agent: AMIPCBridgeDelegate {
	func bridgeDelegate(onReceiveRegister port: UInt32) {
		//Client implementation, ignore
	}
	
	func bridgeDelegate(onReceive message: AMIPCMessage) {
		print("Received IPC message \(message)!")
	}
}
