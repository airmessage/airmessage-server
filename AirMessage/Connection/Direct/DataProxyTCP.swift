//
// Created by Cole Feuer on 2021-11-12.
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
			LogManager.shared.log("Failed to create socket: %{public}", type: .error, errno)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Get address info
		var hints = addrinfo(
				ai_flags: AI_PASSIVE,
				ai_family: AF_UNSPEC,
				ai_socktype: SOCK_STREAM,
				ai_protocol: 0,
				ai_addrlen: 0,
				ai_canonname: nil,
				ai_addr: nil,
				ai_next: nil)
		var servinfo: UnsafeMutablePointer<addrinfo>? = nil
		let addrInfoResult = getaddrinfo(
				nil, //Any interface
				String(port), //The port on which will be listened
				&hints, //Protocol configuration as per above
				&servinfo)
		guard addrInfoResult == 0 else {
			LogManager.shared.log("Failed to get address info: %{public}", type: .error, addrInfoResult)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Bind the socket
		let bindResult = bind(socketFD, servinfo!.pointee.ai_addr, socklen_t(servinfo!.pointee.ai_addrlen))
		guard bindResult == 0 else {
			LogManager.shared.log("Failed to bind socket: %{public}", type: .error, errno)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Set the socket to passive mode
		let listenResult = listen(socketFD, 8)
		guard listenResult == 0 else {
			LogManager.shared.log("Failed to listen socket: %{public}", type: .error, errno)
			
			delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
			return
		}
		
		//Start accepting clients on a background thread
		connectionQueue.async { [weak self] in
			while true {
				var addr = sockaddr()
				var addrLen: socklen_t = 0
				let clientFD = accept(socketFD, &addr, &addrLen)
				guard clientFD != -1 else {
					guard let self = self else { break }
					
					if self.serverRunning {
						//If the user hasn't stopped the server, report the error
						LogManager.shared.log("Failed to accept new client: %{public}", type: .notice, errno)
						self.delegate?.dataProxy(self, didStopWithState: .errorTCPPort, isRecoverable: false)
					}
					break
				}
				
				//Add the client to the list
				guard let self = self else { break }
				let fileHandle = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
				let client = ClientConnectionTCP(id: clientFD, handle: fileHandle, delegate: self)
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
		writeQueue.async {
			//Encrypting the data
			let preparedData: Data
			if encrypt {
				do {
					preparedData = try networkEncrypt(data: data)
				} catch {
					LogManager.shared.log("Failed to encrypt network message: %{public}", type: .error, error.localizedDescription)
					return
				}
			} else {
				preparedData = data
			}
			
			//Sending the data to the client
			(client as! ClientConnectionTCP).write(data: preparedData, isEncrypted: encrypt)
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
				LogManager.shared.log("Failed to decrypt network message: %{public}", type: .error, error.localizedDescription)
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
