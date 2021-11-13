//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation

class DataProxyTCP: DataProxy {
	typealias C = ClientConnectionTCP
	
	weak var delegate: DataProxyDelegate?
	
	let name = "Direct"
	let requiresAuthentication = true
	let requiresPersistence = false
	private(set) var connections: Set<C> = []
	
	private let synchronizationQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.synchronization", qos: .utility)
	private let connectionQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.tcp.connection", qos: .utility, attributes: .concurrent)
	
	private var serverRunning = false
	private var serverSocketFD: Int32?
	
	func startServer() {
		//Ignore if the server is already running
		guard !serverRunning else { return }
		
		//Get the port
		let port = PreferencesManager.shared.serverPort
		
		//Create the socket
		let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
		if socketFD == -1 {
			LogManager.shared.log("Failed to create socket: %{public}", type: .error, errno)
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
		if addrInfoResult != 0 {
			LogManager.shared.log("Failed to get address info: %{public}", type: .error, addrInfoResult)
			return
		}
		
		//Bind the socket
		let bindResult = bind(socketFD, servinfo!.pointee.ai_addr, socklen_t(servinfo!.pointee.ai_addrlen))
		if bindResult != 0 {
			LogManager.shared.log("Failed to bind socket: %{public}", type: .error, errno)
			return
		}
		
		//Set the socket to passive mode
		let listenResult = listen(socketFD, 8)
		if listenResult != 0 {
			LogManager.shared.log("Failed to listen socket: %{public}", type: .error, errno)
			return
		}
		
		//Start accepting clients on a background thread
		connectionQueue.async { [weak self] in
			while true {
				var addr = sockaddr()
				var addrLen: socklen_t = 0
				let clientFD = accept(socketFD, &addr, &addrLen)
				guard clientFD != -1 else {
					LogManager.shared.log("Failed to accept new client, aborting", type: .info)
					break
				}
				
				//Add the client to the list
				guard let self = self else { break }
				let fileHandle = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
				let client = ClientConnectionTCP(id: clientFD, handle: fileHandle, delegate: self)
				self.synchronizationQueue.sync {
					self.connections.insert(client)
				}
				
				//Start the client process
				client.start(on: self.connectionQueue)
			}
		}
		
		serverSocketFD = socketFD
		serverRunning = true
		delegate?.dataProxyDidStart()
	}
	
	func stopServer() {
		//Ignore if the server isn't running
		guard serverRunning, let serverSocketFD = serverSocketFD else { return }
		
		//Disconnect clients
		for client in connections {
			client.stop(cleanup: false)
		}
		
		//Close the file handle
		close(serverSocketFD)
		
		serverRunning = false
		delegate?.dataProxy(didStopWithState: .stopped)
	}
	
	deinit {
		//Make sure we stop the server when we go out of scope
		stopServer()
	}
	
	func send(message data: Data, to client: C, encrypt: Bool, onSent: (() -> ())? = nil) {
	}
	
	func send(pushNotification data: Data, version: Int) {
	}
	
	func disconnect(client: C) {
	}
}

extension DataProxyTCP: ClientConnectionTCPDelegate {
	func clientConnectionTCP(_ client: ClientConnectionTCP, didReceive data: Data, isEncrypted: Bool) {
		//Call the delegate
		guard let delegate = delegate else { return }
		
		delegate.dataProxy(didReceive: data, from: client, wasEncrypted: isEncrypted)
	}
	
	func clientConnectionTCPDidInvalidate(_ client: ClientConnectionTCP) {
		//Remove the client from the list
		connections.remove(client)
		
		//Call the delegate
		delegate?.dataProxy(didDisconnectClient: client)
	}
}