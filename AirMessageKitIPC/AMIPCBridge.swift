//
//  AirMessageKitIPCBridge.swift
//  AirMessageKitIPC
//
//  Created by Cole Feuer on 2022-07-10.
//

import Foundation

public typealias SendMessageCallback = (AMIPCMessage?, Error?) -> Void

public enum AMIPCError: Error {
	case noRemote
	case timeout
}

struct AMIPCBridgePendingRequest {
	var callback: SendMessageCallback
	var timer: Timer
}

///Handles passing AMIPCMessages over a Mach port bridge
@objc public class AMIPCBridge: NSObject {
	//The time interval to use when sending messages
	private static let messageDeadline: TimeInterval = 10
	
	//IPC mach port
	public private(set) var localPort: NSMachPort
	public var remotePort: NSMachPort?
	
	//The next ID to use for message requests
	private var nextID: UInt32 = 0
	
	private var pendingMessageDict: [UInt32: AMIPCBridgePendingRequest] = [:]
	
	public weak var delegate: AMIPCBridgeDelegate?
	
	public static func getMachPort() -> UInt32 {
		var rcv_port: mach_port_name_t = 0
			
		guard mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &rcv_port) == KERN_SUCCESS else {
			fatalError("Failed to setup receive port")
		}
		
		guard mach_port_insert_right(mach_task_self_, rcv_port, rcv_port, .init(MACH_MSG_TYPE_MAKE_SEND)) == KERN_SUCCESS else {
			fatalError("failed to add send right")
		}
		mach_port_insert_member(<#T##task: ipc_space_t##ipc_space_t#>, <#T##name: mach_port_name_t##mach_port_name_t#>, <#T##pset: mach_port_name_t##mach_port_name_t#>)
		
		return rcv_port
	}
	
	public init(forRemotePort remotePort: NSMachPort? = nil, withLocalPort localPort: NSMachPort = NSMachPort(machPort: AMIPCBridge.getMachPort())) {
		self.localPort = localPort
		self.remotePort = remotePort
		
		super.init()
		
		//Set the port delegate
		self.localPort.setDelegate(self)
		
		//Add the port to the run loop
		self.localPort.schedule(in: RunLoop.current, forMode: .default)
		
		//Register ports
		registerPorts()
	}
	
	public func registerPorts() {
		var server_port = mach_port_t(localPort.machPort)
		mach_ports_register(mach_task_self_, &server_port, 1)
	}
	
	///Notifies the remote of this connection
	public func notifyRegistration() throws {
		guard let remotePort = remotePort else {
			throw AMIPCError.noRemote
		}
		
		let portMessage = PortMessage(send: remotePort, receive: nil, components: [localPort.machPort])
		portMessage.msgid = AMIPCType.register.rawValue
		portMessage.send(before: Date.init(timeIntervalSinceNow: AMIPCBridge.messageDeadline))
	}
	
	///Send a message via fire-and-forget
	public func send(message: AMIPCMessage) throws {
		guard let remotePort = remotePort else {
			throw AMIPCError.noRemote
		}
		
		//Send the message
		let portMessage = PortMessage(send: remotePort, receive: nil, components: [try message.encodeToData()])
		portMessage.msgid = AMIPCType.notify.rawValue
		portMessage.send(before: Date.init(timeIntervalSinceNow: AMIPCBridge.messageDeadline))
	}
	
	///Send a message and wait for a response
	public func send(message: AMIPCMessage, callback: @escaping SendMessageCallback) {
		guard let remotePort = remotePort else {
			callback(nil, AMIPCError.noRemote)
			return
		}
		
		let messageData: Data
		do {
			messageData = try message.encodeToData()
		} catch {
			callback(nil, error)
			return
		}
		
		//Send the message
		let portMessage = PortMessage(send: remotePort, receive: localPort, components: [messageData])
		portMessage.msgid = AMIPCType.request.rawValue
		portMessage.send(before: Date.init(timeIntervalSinceNow: AMIPCBridge.messageDeadline))
		
		//Schedule a deadline
		let timer = Timer.scheduledTimer(withTimeInterval: AMIPCBridge.messageDeadline, repeats: false) { [weak self] timer in
			guard let self = self else { return }
			
			//Cancel the pending request and report a failure
			self.pendingMessageDict[message.id] = nil
			callback(nil, AMIPCError.timeout)
		}
		
		//Register the request for a reply
		pendingMessageDict[message.id] = AMIPCBridgePendingRequest(
			callback: callback,
			timer: timer
		)
	}
}

extension AMIPCBridge: NSMachPortDelegate {
	public func handle(_ portMessage: PortMessage) {
		//Map the port message ID
		guard let type = AMIPCType(rawValue: portMessage.msgid) else {
			print("Received unknown AMIPCBridge port message ID \(portMessage.msgid)")
			return
		}
		
		//Handle registrations
		if type == .register {
			//Decode the message
			guard let components = portMessage.components,
				  components.count == 1,
				  let remotePortRaw = components[0] as? UInt32 else {
				print("Received invalid AMIPCBridge register payload")
				return
			}
			
			//Set the remote port
			print("Received registration payload")
			remotePort = NSMachPort(machPort: remotePortRaw)
			
			//Notify the delegate
			delegate?.bridgeDelegate(onReceiveRegister: remotePortRaw)
			
			return
		}
		
		//Decode the message
		let amMessage: AMIPCMessage
		do {
			amMessage = try AMIPCMessage.fromPortMessage(portMessage)
		} catch {
			print("Failed to decode AMIPCBridge port message for \(type): \(error)")
			return
		}
		
		if type == .notify {
			//Call the delegate
			delegate?.bridgeDelegate(onReceive: amMessage)
		} else if type == .request {
			DispatchQueue.main.async { [weak self, amMessage] in
				guard let self = self else { return }
				
				//Find a matching pending request
				guard let request = self.pendingMessageDict[amMessage.id] else {
					return
				}
				
				//Clear the pending request
				self.pendingMessageDict[amMessage.id] = nil
				
				//Cancel the timeout timer
				request.timer.invalidate()
				
				//Invoke the callback
				request.callback(amMessage, nil)
			}
		}
	}
}

public protocol AMIPCBridgeDelegate : AnyObject {
	///Handles when a new client is registered
	func bridgeDelegate(onReceiveRegister port: UInt32)
	
	///Handles when a receive value is received
	func bridgeDelegate(onReceive message: AMIPCMessage)
}
