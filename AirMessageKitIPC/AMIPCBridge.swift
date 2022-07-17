//
//  AirMessageKitIPCBridge.swift
//  AirMessageKitIPC
//
//  Created by Cole Feuer on 2022-07-10.
//

import Foundation
import LocalUtils

public typealias SendMessageCallback = (AMIPCMessage?, Error?) -> Void

public enum AMSocketError: Error {
	case invalidPath
	case socketError(POSIXErrorCode?)
	case timeoutError
}

public enum AMIPCError: Error {
	case noRemote
	case timeout
}

struct AMIPCBridgePendingRequest {
	var callback: SendMessageCallback
	var timer: DispatchSourceTimer
}

///Handles passing AMIPCMessages over an inter-process bridge
public class AMIPCBridge {
	private static let clientWaitTimeout: TimeInterval = 20
	private static let requestTimeout: TimeInterval = 20
	
	private let socketFile: URL
	
	//Dispatch queues
	private let serverQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".amipc.server", qos: .utility, attributes: [.concurrent])
	private let requestQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".amipc.request", qos: .utility)
	private let readQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".amipc.read", qos: .utility)
	
	private var socketHandle: FileHandle?
	
	//The next ID to use for message requests
	private var nextID: UInt32 = 0
	
	private var pendingMessageDict: [UInt32: AMIPCBridgePendingRequest] = [:]
	
	public weak var delegate: AMIPCBridgeDelegate?
	
	public init(withSocketFile socketFile: URL) {
		self.socketFile = socketFile
	}
	
	///Starts the server and waits for a specified timeout for a client to connect
	public func receiveClient() {
		//Create the socket
		let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
		guard socketFD != -1 else {
			delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
			return
		}
		
		do {
			//Prepare the socket address
			var address = sockaddr_un()
			
			let filePath = socketFile.path
			let filePathLength = filePath.withCString { Int(strlen($0)) }
			guard filePathLength < MemoryLayout.size(ofValue: address.sun_path) else {
				delegate?.bridgeDelegate(onError: AMSocketError.invalidPath)
				return
			}
			
			address.sun_family = sa_family_t(AF_UNIX)
			_ = withUnsafeMutablePointer(to: &address.sun_path.0) { destPr in
				socketFile.path.withCString { stringPtr in
					strncpy(destPr, stringPtr, filePathLength)
				}
			}
			
			//Bind the socket
			let addressSize = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + filePathLength)
			let bindResult = withUnsafePointer(to: &address) { ptr in
				ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
					bind(socketFD, ptr, addressSize)
				}
			}
			guard bindResult == 0 else {
				delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				return
			}
			
			//Start listening on the socket
			let listenResult = listen(socketFD, 1)
			guard listenResult == 0 else {
				delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				return
			}
		}
		
		//Start the timeout timer
		let timer = DispatchSource.makeTimerSource(queue: serverQueue)
		timer.schedule(deadline: .now() + AMIPCBridge.clientWaitTimeout, repeating: .never)
		timer.setEventHandler {
			//Close the server socket
			close(socketFD)
			print("Client accept timed out!")
		}
		timer.resume()
		
		serverQueue.async { [weak self] in
			print("Accepting client...")
			//Accept the first client
			let clientFD = accept(socketFD, nil, nil)
			print("Client accepted!")
			
			//Cancel the timer
			timer.cancel()
			
			guard let self = self else { return }
			
			//Make sure the accept succeeded
			guard clientFD != -1 else {
				print("Client accept failed!")
				self.delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				return
			}
			
			//Close the server socket to stop listening for new connections
			guard close(socketFD) == 0 else {
				self.delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				return
			}
			
			//Set the socket handle
			let socketHandle = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
			self.requestQueue.sync {
				self.socketHandle = socketHandle
			}
			
			//Notify that we've connected successfully
			self.delegate?.bridgeDelegateOnConnect()
			
			//Start reading incoming messages
			self.readIncomingMessages(forFileHandle: socketHandle)
		}
	}
	
	///Starts the client and attempts to connect to the server
	public func connectClient() {
		//Create the socket
		let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
		guard socketFD != -1 else {
			delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
			return
		}
		
		//Prepare the socket address
		var address = sockaddr_un()
		
		let filePath = socketFile.path
		let filePathLength = filePath.withCString { strlen($0) }
		guard filePathLength < MemoryLayout.size(ofValue: address.sun_path) else {
			delegate?.bridgeDelegate(onError: AMSocketError.invalidPath)
			return
		}
		
		address.sun_family = sa_family_t(AF_UNIX)
		_ = withUnsafeMutablePointer(to: &address.sun_path.0) { destPr in
			socketFile.path.withCString { stringPtr in
				strncpy(destPr, stringPtr, filePathLength)
			}
		}
		
		serverQueue.async { [weak self] in
			print("Start client connection to \(filePath)...")
			
			//Connect the socket
			let addressSize = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + filePathLength)
			let connectResult = withUnsafePointer(to: &address) { ptr in
				ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
					connect(socketFD, ptr, addressSize)
				}
			}
			
			guard let self = self else { return }
			
			guard connectResult == 0 else {
				print("Got connect result \(connectResult) with code \(POSIXError.Code(rawValue: errno)!))")
				self.delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				return
			}
			
			print("Finish client connection!")
			
			//Set the socket handle
			let socketHandle = FileHandle(fileDescriptor: socketFD, closeOnDealloc: true)
			self.requestQueue.sync { [weak self] in
				guard let self = self else { return }
				self.socketHandle = socketHandle
			}
			
			//Notify that we've connected successfully
			self.delegate?.bridgeDelegateOnConnect()
			
			//Start reading incoming messages
			self.readIncomingMessages(forFileHandle: socketHandle)
		}
	}
	
	///Loops infinitely and reads incoming messages on the file handle
	private func readIncomingMessages(forFileHandle fileHandle: FileHandle) {
		while true {
			do {
				//Read the message
				let data = try AMIPCBridge.read(fromHandle: fileHandle)
				
				//Decode the message
				let amMessage: AMIPCMessage
				amMessage = try PropertyListDecoder().decode(AMIPCMessage.self, from: data)
				
				requestQueue.async { [weak self] in
					guard let self = self else { return }
					
					//Find a matching pending request
					if let request = self.pendingMessageDict[amMessage.id] {
						//Clear the pending request
						self.pendingMessageDict[amMessage.id] = nil
						
						//Cancel the timeout timer
						request.timer.cancel()
						
						//Invoke the callback
						request.callback(amMessage, nil)
					} else {
						//Notify the delegate of a new incoming message
						self.delegate?.bridgeDelegate(onReceive: amMessage)
					}
				}
			} catch {
				//Invalidate the socket handle and report the error
				requestQueue.async {
					self.socketHandle = nil
					try? fileHandle.closeCompat()
					self.delegate?.bridgeDelegate(onError: AMSocketError.socketError(POSIXErrorCode(rawValue: errno)))
				}
				
				break
			}
		}
	}
	
	///Sends a message via fire-and-forget
	/// - Parameters:
	///   - message: The message to send
	///   - callback: A callback invoked with an error if the message failed to send,
	///				  or nil if the message was sent successfully
	public func send(message: AMIPCMessage, callback: ((Error?) -> Void)? = nil) {
		//Get the socket handle
		guard let socketHandle = socketHandle else {
			callback?(AMIPCError.noRemote)
			return
		}
		
		requestQueue.async {
			do {
				let data = try message.encodeToData()
				try AMIPCBridge.write(data: data, toHandle: socketHandle)
			} catch {
				callback?(error)
				return
			}
			
			//OK
			callback?(nil)
		}
	}
	
	///Sends a message and listens for a response
	/// - Parameters:
	///   - message: The message to send
	///   - callback: A callback invoked with the response message, or an error if th message failed
	public func send(message: AMIPCMessage, callback: @escaping SendMessageCallback) {
		//Get the socket handle
		guard let socketHandle = socketHandle else {
			callback(nil, AMIPCError.noRemote)
			return
		}
		
		requestQueue.async {
			//Send the message
			do {
				let data = try message.encodeToData()
				try AMIPCBridge.write(data: data, toHandle: socketHandle)
			} catch {
				callback(nil, error)
				return
			}
			
			//Schedule a deadline
			let timer = DispatchSource.makeTimerSource(queue: self.requestQueue)
			timer.schedule(deadline: .now() + AMIPCBridge.requestTimeout, repeating: .never)
			timer.setEventHandler { [weak self] in
				guard let self = self else { return }
				
				//Cancel the pending request and report a failure
				self.pendingMessageDict[message.id] = nil
				callback(nil, AMIPCError.timeout)
			}
			timer.resume()
			
			//Register the request for a reply
			self.pendingMessageDict[message.id] = AMIPCBridgePendingRequest(
					callback: callback,
					timer: timer
			)
		}
	}
	
	///Writes a block of data to the receiver
	private static func write(data: Data, toHandle handle: FileHandle) throws {
		try handle.writeCompat(contentsOf: withUnsafeBytes(of: Int(data.count)) { Data($0) })
		try handle.writeCompat(contentsOf: data)
	}
	
	///Reads a block of data from the sender
	private static func read(fromHandle handle: FileHandle) throws -> Data {
		let length = try handle.readCompat(upToCount: MemoryLayout<Int>.size)
				.withUnsafeBytes { $0.load(as: Int.self) }
		return try handle.readCompat(upToCount: length)
	}
}

public protocol AMIPCBridgeDelegate : AnyObject {
	///Handles when a client is connected
	func bridgeDelegateOnConnect()
	
	///Handles any errors
	func bridgeDelegate(onError error: Error)
	
	///Handles when a receive value is received
	func bridgeDelegate(onReceive message: AMIPCMessage)
}
