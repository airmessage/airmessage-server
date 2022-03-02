//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-12.
//

import Foundation
import Sentry

class DataProxyTCP: DataProxy {
	weak var delegate: DataProxyDelegate?
	
	let name = "Direct"
	let requiresPersistence = true
	let supportsPushNotifications = false
	private var connectionsMap: [Int32: ClientConnectionTCP] = [:]
	var connections: [ClientConnection] { Array(connectionsMap.values) }
	let connectionsLock = ReadWriteLock()
	
	private let serverPort: Int
	
	private let connectionQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.connection", qos: .utility, attributes: .concurrent) //Long-running operations for connections
	private let writeQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.write", qos: .utility) //Write requests
	
	private var serverRunning = false
	private var serverSocketHandle: FileHandle?
	
	init(port: Int) {
		serverPort = port
	}
	
	func startServer() {
		//Ignore if the server is already running
		guard !serverRunning else { return }
		
		//Create the socket
		let socketHandle: FileHandle
		do {
			let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
			guard socketFD != -1 else {
				LogManager.log("Failed to create socket: \(errno)", level: .error)
				
				delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
				return
			}
			socketHandle = FileHandle(fileDescriptor: socketFD, closeOnDealloc: true)
		}
		
		//Configure the socket
		var opt: Int32 = -1
		let setOptResult = setsockopt(socketHandle.fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
		guard setOptResult == 0 else {
			LogManager.log("Failed to set socket opt: \(errno)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Bind the socket
		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = INADDR_ANY
		address.sin_port = in_port_t(Int16(serverPort).bigEndian)
		let bindResult = withUnsafePointer(to: &address) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
				bind(socketHandle.fileDescriptor, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bindResult == 0 else {
			LogManager.log("Failed to bind socket: \(errno) on port \(serverPort)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Set the socket to passive mode
		let listenResult = listen(socketHandle.fileDescriptor, 8)
		guard listenResult == 0 else {
			LogManager.log("Failed to listen socket: \(errno)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Start accepting clients on a background thread
		connectionQueue.async { [weak self] in
			while true {
				var addr = sockaddr()
				var addrLen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
				let clientFD = accept(socketHandle.fileDescriptor, &addr, &addrLen)
				guard clientFD != -1 else {
					guard let self = self else { return }
					
					if self.serverRunning {
						//If the user hasn't stopped the server, report the error
						LogManager.log("Failed to accept new client: \(errno)", level: .notice)
						self.delegate?.dataProxy(self, didStopWithState: .errorTCPInternal, isRecoverable: false)
					}
					return
				}
				
				//Get the client address
				let clientAddress: String
				switch Int32(addr.sa_family) {
					case AF_INET:
						var addrIPV4 = unsafeBitCast(addr, to: sockaddr_in.self)
						
						let resultPtr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET_ADDRSTRLEN))
						defer { resultPtr.deallocate() }
						
						inet_ntop(AF_INET, &(addrIPV4.sin_addr), resultPtr, socklen_t(INET_ADDRSTRLEN))
						
						clientAddress = String(cString: resultPtr)
						
						break
					case AF_INET6:
						var addrIPV6 = unsafeBitCast(addr, to: sockaddr_in6.self)
						
						let resultPtr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET6_ADDRSTRLEN))
						defer { resultPtr.deallocate() }
						
						inet_ntop(AF_INET, &(addrIPV6.sin6_addr), resultPtr, socklen_t(INET6_ADDRSTRLEN))
						
						clientAddress = String(cString: resultPtr)
						
						break
					default:
						LogManager.log("Client connected with unknown address family \(addr.sa_family)", level: .error)
						
						guard let self = self else { return }
						self.delegate?.dataProxy(self, didStopWithState: .errorTCPInternal, isRecoverable: false)
						return
				}
				
				//Add the client to the list
				guard let self = self else { break }
				let (connectionCount, client, isClientNew) = self.connectionsLock.withWriteLock { () -> (Int, ClientConnectionTCP, Bool) in
					if let existingClient = self.connectionsMap[clientFD] {
						//Reset the existing client
						existingClient.reset()
						
						return (self.connectionsMap.count, existingClient, false)
					} else {
						//Create a new client
						let fileHandle = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
						let newClient = ClientConnectionTCP(id: clientFD, handle: fileHandle, address: clientAddress, delegate: self)
						self.connectionsMap[clientFD] = newClient
						
						return (self.connectionsMap.count, newClient, true)
					}
				}
				
				if isClientNew {
					LogManager.log("Client connected from \(clientAddress)", level: .info)
					
					//Start the client process
					client.start(on: self.connectionQueue)
				} else {
					LogManager.log("Client reconnected from \(clientAddress)", level: .info)
				}
				
				//Notify the delegate
				self.delegate?.dataProxy(self, didConnectClient: client, totalCount: connectionCount)
			}
		}
		
		serverSocketHandle = socketHandle
		serverRunning = true
		delegate?.dataProxyDidStart(self)
	}
	
	func stopServer() {
		//Ignore if the server isn't running
		guard serverRunning else { return }
		serverRunning = false
		
		//Disconnect clients
		for client in connections {
			(client as! ClientConnectionTCP).stop(cleanup: false)
		}
		NotificationNames.postUpdateConnectionCount(0)
		
		//Close the file handle
		try? serverSocketHandle?.closeCompat()
		serverSocketHandle = nil
		
		//Notify the delegate
		delegate?.dataProxy(self, didStopWithState: .stopped, isRecoverable: false)
	}
	
	deinit {
		//Make sure we stop the server when we go out of scope
		stopServer()
	}
	
	func send(message data: Data, to client: ClientConnection?, encrypt: Bool, onSent: (() -> ())?) {
		writeQueue.async { [weak self] in
			//Encrypting the data
			let preparedData: Data
			if encrypt {
				do {
					preparedData = try networkEncrypt(data: data)
				} catch {
					LogManager.log("Failed to encrypt network message: \(error)", level: .error)
					SentrySDK.capture(error: error)
					return
				}
			} else {
				preparedData = data
			}
			
			if let client = client {
				//Sending the data to the client
				(client as! ClientConnectionTCP).write(data: preparedData, isEncrypted: encrypt)
			} else {
				guard let self = self else { return }
				
				//Copy the connections set
				let connections = self.connectionsLock.withReadLock { self.connectionsMap.values }
				
				//Send the data to all clients
				for client in connections {
					//If this data is encrypted, don't send it to unregistered clients
					if encrypt && client.registration == nil {
						continue
					}
					
					client.write(data: preparedData, isEncrypted: encrypt)
				}
			}
			
			//Invoke the sent callback
			onSent?()
		}
	}
	
	func send(pushNotification data: Data, version: Int) {
		//Not supported
	}
	
	func disconnect(client: ClientConnection) {
		(client as! ClientConnectionTCP).stop(cleanup: true)
	}
}

extension DataProxyTCP: ClientConnectionTCPDelegate {
	func clientConnectionTCP(_ client: ClientConnectionTCP, didReceive data: Data, isEncrypted: Bool) {
		guard let delegate = delegate else { return }
		
		//Decrypt the data if it's encrypted
		let decryptedData: Data
		if isEncrypted {
			do {
				decryptedData = try networkDecrypt(data: data)
			} catch {
				LogManager.log("Failed to decrypt network message: \(error)", level: .error)
				return
			}
		} else {
			decryptedData = data
		}
		
		//Call the delegate
		delegate.dataProxy(self, didReceive: decryptedData, from: client, wasEncrypted: isEncrypted)
	}
	
	func clientConnectionTCPDidInvalidate(_ client: ClientConnectionTCP) {
		//Remove the client from the list
		let connectionCount = connectionsLock.withWriteLock { () -> Int in
			connectionsMap[client.id] = nil
			return connections.count
		}
		
		//Call the delegate
		delegate?.dataProxy(self, didDisconnectClient: client, totalCount: connectionCount)
	}
}
