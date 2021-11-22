//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-12.
//

import Foundation

class DataProxyTCP: DataProxy {
	weak var delegate: DataProxyDelegate?
	
	let name = "Direct"
	let requiresAuthentication = true
	let requiresPersistence = true
	let supportsPushNotifications = false
	private(set) var connections: Set<ClientConnection> = []
	let connectionsLock = NSLock()
	
	private let connectionQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.connection", qos: .utility, attributes: .concurrent) //Long-running operations for connections
	private let writeQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.write", qos: .utility) //Write requests
	
	private var serverRunning = false
	private var serverSocketFD: Int32?
	
	func startServer() {
		//Ignore if the server is already running
		guard !serverRunning else { return }
		
		//Get the port
		let port = PreferencesManager.shared.serverPort
		
		//Create the socket
		let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
		guard socketFD != -1 else {
			LogManager.log("Failed to create socket: \(errno)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Configure the socket
		var opt: Int32 = -1
		let setOptResult = setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
		guard setOptResult == 0 else {
			LogManager.log("Failed to set socket opt: \(errno)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Bind the socket
		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = INADDR_ANY
		address.sin_port = in_port_t(Int16(port).bigEndian)
		let bindResult = withUnsafePointer(to: address) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
				bind(socketFD, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bindResult == 0 else {
			LogManager.log("Failed to bind socket: \(errno) on port \(port)", level: .error)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Set the socket to passive mode
		let listenResult = listen(socketFD, 8)
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
				let clientFD = accept(socketFD, &addr, &addrLen)
				guard clientFD != -1 else {
					guard let self = self else { return }
					
					if self.serverRunning {
						//If the user hasn't stopped the server, report the error
						LogManager.log("Failed to accept new client: \(errno)", level: .notice)
						self.delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
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
				
				LogManager.log("Client connected from \(clientAddress)", level: .info)
				
				//Add the client to the list
				guard let self = self else { break }
				let fileHandle = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
				let client = ClientConnectionTCP(id: clientFD, handle: fileHandle, address: clientAddress, delegate: self)
				let connectionCount: Int
				do {
					self.connectionsLock.lock()
					defer { self.connectionsLock.unlock() }
					
					self.connections.insert(client)
					connectionCount = self.connections.count
				}
				
				//Start the client process
				client.start(on: self.connectionQueue)
				
				//Notify the delegate
				self.delegate?.dataProxy(self, didConnectClient: client, totalCount: connectionCount)
			}
		}
		
		serverSocketFD = socketFD
		serverRunning = true
		delegate?.dataProxyDidStart(self)
	}
	
	func stopServer() {
		//Ignore if the server isn't running
		guard serverRunning, let serverSocketFD = serverSocketFD else { return }
		
		//Disconnect clients
		for client in connections {
			(client as! ClientConnectionTCP).stop(cleanup: false)
		}
		
		//Close the file handle
		close(serverSocketFD)
		
		serverRunning = false
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
					return
				}
			} else {
				preparedData = data
			}
			
			if let client = client {
				//Sending the data to the client
				(client as! ClientConnectionTCP).write(data: preparedData, isEncrypted: encrypt)
			} else {
				//Copy the connections set
				let connections: Set<ClientConnection>
				do {
					guard let self = self else { return }
					
					self.connectionsLock.lock()
					defer { self.connectionsLock.unlock() }
					connections = self.connections
				}
				
				//Send the data to all clients
				for client in connections {
					(client as! ClientConnectionTCP).write(data: preparedData, isEncrypted: encrypt)
				}
			}
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
		let connectionCount: Int
		do {
			connectionsLock.lock()
			defer { connectionsLock.unlock() }
			
			connections.remove(client)
			connectionCount = connections.count
		}
		
		//Call the delegate
		delegate?.dataProxy(self, didDisconnectClient: client, totalCount: connectionCount)
	}
}
