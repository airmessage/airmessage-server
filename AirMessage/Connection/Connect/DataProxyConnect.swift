//
//  DataProxyConnect.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-23.
//

import Foundation
import NIO
import NIOSSL
import NIOWebSocket
import WebSocketKit
import Sentry

class DataProxyConnect: DataProxy {
	weak var delegate: DataProxyDelegate?
	
	let name = "Connect"
	let requiresPersistence = false
	let supportsPushNotifications = true
	private var connectionsMap: [Int32: ClientConnection] = [:]
	var connections: [ClientConnection] { Array(connectionsMap.values) }
	let connectionsLock = ReadWriteLock()
	
	private let userID: String
	private var idToken: String?
	
	private var webSocket: WebSocket?
	private var handshakeTimer: DispatchSourceTimer?
	
	private var pingTimer: DispatchSourceTimer?
	private static let pingFrequency: TimeInterval = 5 * 60
	
	private var pingResponseTimer: DispatchSourceTimer?
	private static let pingResponseTimeout: TimeInterval = 60
	
	private var connectionRecoveryTimer: DispatchSourceTimer?
	private var connectionRecoveryCount = 0
	//The max num of attempts before capping the delay time - not before giving up
	private static let connectionRecoveryCountMax = 8
	
	private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
	private let processingQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.connect.processing", qos: .utility)
	
	private var isActive = false
	
	init(userID: String, idToken: String? = nil) {
		self.userID = userID
		self.idToken = idToken
	}
	
	deinit {
		//Shut down the event loop
		try? eventLoopGroup.syncShutdownGracefully()
		
		//Ensure the server proxy isn't running when we go out of scope
		assert(!isActive, "DataProxyConnect was deinitialized while active")
		
		//Ensure timers are cleaned up
		assert(pingTimer == nil, "DataProxyConnect was deinitialized with an active ping timer")
		assert(handshakeTimer == nil, "DataProxyConnect was deinitialized with an active handshake timer")
		assert(connectionRecoveryTimer == nil, "DataProxyConnect was deinitialized with an active connection recovery timer")
	}
	
	func startServer() {
		assertDispatchQueue(DispatchQueue.main)
		
		//Ignore if we're already connecting or connected
		guard !isActive else { return }
		
		//Cancel any active connection recover timers (in case the user initiated a reconnect)
		processingQueue.sync {
			stopConnectionRecoveryTimer()
		}
		
		//Build the URL
		var queryItems = [
			URLQueryItem(name: "communications", value: String(ConnectConstants.commVer)),
			URLQueryItem(name: "is_server", value: String(true)),
			URLQueryItem(name: "installation_id", value: PreferencesManager.shared.installationID)
		]
		if let idToken = idToken {
			queryItems.append(URLQueryItem(name: "id_token", value: idToken))
		} else {
			queryItems.append(URLQueryItem(name: "user_id", value: userID))
		}
		var components = URLComponents(string: Bundle.main.infoDictionary!["CONNECT_ENDPOINT"] as! String)!
		components.queryItems = queryItems
		
		var headers = HTTPHeaders()
		headers.add(name: "Origin", value: "app")
		
		//Create the WebSocket connection
		var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
		if #available(macOS 10.13, *) {
			
		} else {
			let certificates = CertificateTrust.certificateFiles.map { certificateURL in try! NIOSSLCertificate(file: certificateURL.path, format: .der) }
			tlsConfiguration.additionalTrustRoots = [.certificates(certificates)]
			tlsConfiguration.trustRoots = .certificates([])
		}
		let webSocketConfiguration = WebSocketClient.Configuration(
			tlsConfiguration: tlsConfiguration,
			maxFrameSize: 1024 * 1024 * 100 //100 MB
		)
		
		WebSocket.connect(to: components.url!, headers: headers, configuration: webSocketConfiguration, on: eventLoopGroup, onUpgrade: { [weak self] webSocket in
			//Report open event
			let webSocketOK = self?.processingQueue.sync { [weak self] () -> Bool in
				guard let self = self else { return false }
				
				//Ignore if the connection has been cancelled in the meantime
				guard self.isActive else { return false }
				
				self.webSocket = webSocket
				self.onWSConnect()
				
				return true
			}
			
			//If we've decided we don't want this connection anymore, disconnect
			//it and discard it silently
			guard let webSocketOK = webSocketOK, webSocketOK else {
				_ = webSocket.close()
				return
			}
			
			//Set the listeners
			webSocket.onBinary { [weak self] _, byteBuffer in
				self?.processingQueue.async { [weak self] in
					self?.onWSReceive(data: Data(byteBuffer.readableBytesView))
				}
			}
			webSocket.onClose.whenComplete { [weak self] result in
				self?.processingQueue.async { [weak self] in
					switch result {
						case .failure(let error):
							self?.onWSError(error: error)
						case .success(_):
							self?.onWSDisconnect(withCode: webSocket.closeCode ?? WebSocketErrorCode.normalClosure)
					}
				}
			}
			webSocket.onPong { [weak self] _ in
				self?.processingQueue.async { [weak self] in
					self?.onWSPong()
				}
			}
		}).whenFailure { [weak self] error in
			self?.processingQueue.async { [weak self] in
				self?.onWSError(error: error)
			}
		}
		
		isActive = true
	}
	
	func stopServer() {
		assertDispatchQueue(DispatchQueue.main)
		
		//Ignore if we're not running
		guard isActive else { return }
		
		processingQueue.sync {
			//Clear connected clients
			connectionsLock.withWriteLock {
				connectionsMap.removeAll()
			}
			NotificationNames.postUpdateConnectionCount(0)
			
			//Socket can be nil between calls to startServer()
			//and WebSocket.connect's result handler
			if let socket = webSocket {
				_ = socket.close()
			}
			
			delegate?.dataProxy(self, didStopWithState: .stopped, isRecoverable: false)
		}
		
		isActive = false
	}
	
	func send(message data: Data, to client: ClientConnection?, encrypt: Bool, onSent: (() -> ())?) {
		guard let socket = webSocket else { return }
		
		//Encrypting the content if requested and a password is set
		let secureData: Data
		let supportsEncryption = !PreferencesManager.shared.password.isEmpty
		let isEncrypted = encrypt && supportsEncryption
		if isEncrypted {
			do {
				secureData = try networkEncrypt(data: data)
			} catch {
				LogManager.log("Failed to encrypt data for Connect proxy: \(error)", level: .error)
				SentrySDK.capture(error: error)
				return
			}
		} else {
			secureData = data
		}
		
		//Create the message
		var packer = BytePacker()
		if let client = client {
			packer.pack(int: ConnectNHT.serverProxy.rawValue)
			packer.pack(int: client.id)
		} else {
			packer.pack(int: ConnectNHT.serverProxyBroadcast.rawValue)
		}
		if isEncrypted {
			//The content is encrypted
			packer.pack(byte: -100)
		} else if supportsEncryption {
			//We support encryption, but this packet isn't encrypted
			packer.pack(byte: -101)
		} else {
			//We don't support encryption
			packer.pack(byte: -102)
		}
		packer.pack(data: secureData)
		
		//Send the message
		if let onSent = onSent {
			let promise = eventLoopGroup.next().makePromise(of: Void.self)
			socket.send([UInt8](packer.data), promise: promise)
			promise.futureResult.whenSuccess(onSent)
		} else {
			socket.send([UInt8](packer.data))
		}
	}
	
	func send(pushNotification data: Data, version: Int) {
		guard let socket = webSocket else { return }
		
		//Create the message
		var packer = BytePacker(capacity: MemoryLayout<Int32>.size * 6 + data.count)
		packer.pack(int: ConnectNHT.serverNotifyPush.rawValue)
		packer.pack(int: Int32(version))
		packer.pack(int: 2)
		packer.pack(int: CommConst.version)
		packer.pack(int: CommConst.subVersion)
		packer.pack(data: data)
		
		//Send the message
		socket.send([UInt8](packer.data))
	}
	
	func disconnect(client: ClientConnection) {
		disconnect(clientID: client.id)
	}
	
	private func disconnect(clientID: Int32) {
		guard let socket = webSocket else { return }
		
		//Create the message
		var packer = BytePacker(capacity: MemoryLayout<Int32>.size * 2)
		packer.pack(int: ConnectNHT.serverClose.rawValue)
		packer.pack(int: clientID)
		
		//Send the message
		socket.send([UInt8](packer.data))
		
		//Remove the client
		removeClient(clientID: clientID)
	}
	
	/**
	 Sets this proxy as registered, such that future requests will not try to re-register this server
	 */
	func setRegistered() {
		idToken = nil
	}
	
	//MARK: Ping timer
	
	private func startPingTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Cancel the old timer
		pingTimer?.cancel()
		
		//Create the new timer
		let timer = DispatchSource.makeTimerSource(queue: processingQueue)
		timer.schedule(deadline: .now() + DataProxyConnect.pingFrequency, repeating: DataProxyConnect.pingFrequency)
		timer.setEventHandler(handler: onPingTimer)
		timer.resume()
		pingTimer = timer
	}
	
	private func stopPingTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		pingTimer?.cancel()
		pingTimer = nil
	}
	
	private func onPingTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Ping
		webSocket?.sendPing()
		
		//Wait for a pong
		startPingResponseTimer()
	}
	
	private func startPingResponseTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Cancel the old timer
		pingResponseTimer?.cancel()
		
		//Create the new timer
		let timer = DispatchSource.makeTimerSource(queue: processingQueue)
		timer.schedule(deadline: .now() + DataProxyConnect.pingResponseTimeout, repeating: .never)
		timer.setEventHandler(handler: onPingResponseTimer)
		timer.resume()
		pingResponseTimer = timer
	}
	
	private func stopPingResponseTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		pingResponseTimer?.cancel()
		pingResponseTimer = nil
	}
	
	private func onPingResponseTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		LogManager.log("Didn't receive a pong response from Connect proxy, disconnecting", level: .info)
		
		//Didn't receive a pong from the server in time! Disconnect
		onWSDisconnect(withCode: .normalClosure)
		
		//Disconnect
		_ = webSocket?.close()
	}
	
	//MARK: Handshake Timer
	
	private func startHandshakeTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Cancel the old timer
		handshakeTimer?.cancel()
		
		//Create the new timer
		let timer = DispatchSource.makeTimerSource(queue: processingQueue)
		timer.schedule(deadline: .now() + ConnectConstants.handshakeTimeout, repeating: .never)
		timer.setEventHandler(handler: onHandshakeTimer)
		timer.resume()
		handshakeTimer = timer
	}
	
	private func stopHandshakeTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		handshakeTimer?.cancel()
		handshakeTimer = nil
	}
	
	private func onHandshakeTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Disconnect
		_ = webSocket?.close()
		
		//Clean up
		stopHandshakeTimer()
	}
	
	//MARK: Connection recovery timer
	
	private func startConnectionRecoveryTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		//Cancel the old timer
		connectionRecoveryTimer?.cancel()
		
		//Wait an exponentially increasing wait period + a random delay
		let randomOffset: TimeInterval = Double(arc4random()) / Double(UInt32.max)
		let delay: TimeInterval = pow(2, Double(connectionRecoveryCount)) + randomOffset
		
		//Create the new timer
		//startServer() must be invoked from the main thread
		let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
		timer.schedule(deadline: .now() + delay, repeating: .never)
		timer.setEventHandler(handler: startServer)
		timer.resume()
		connectionRecoveryTimer = timer
		
		//Add to the attempt counter
		if connectionRecoveryCount < DataProxyConnect.connectionRecoveryCountMax {
			connectionRecoveryCount += 1
		}
	}
	
	private func stopConnectionRecoveryTimer() {
		//Make sure we're on the processing queue
		assertDispatchQueue(processingQueue)
		
		connectionRecoveryTimer?.cancel()
		connectionRecoveryTimer = nil
	}
	
	//MARK: Event handling
	
	private func onWSConnect() {
		LogManager.log("Connection to Connect relay opened", level: .info)
		
		//Start the ping timer
		startPingTimer()
		
		//Start the handshake timer
		startHandshakeTimer()
	}
	
	private func onWSDisconnect(withCode code: WebSocketErrorCode) {
		LogManager.log("Connection to Connect relay lost: \(code)", level: .info)
		
		//Stop timers
		stopPingTimer()
		stopPingResponseTimer()
		stopHandshakeTimer()
		
		//Update the active state
		DispatchQueue.main.async { [weak self] in
			self?.isActive = false
		}
		
		//Map the error code
		let localError: ServerState
		switch code {
			case .normalClosure, .unexpectedServerError:
				localError = .errorInternet
			case .protocolError, .policyViolation:
				localError = .errorConnBadRequest
			case .unknown(let rawCode):
				switch rawCode {
					//Other WebSocket close codes
					case 1012, //Server error
						1013, //Service restart
						1014, //Try again later
						1015: //Bad gateway
						localError = .errorInternet
					//Custom AirMessage codes
					case ConnectCloseCode.incompatibleProtocol.rawValue:
						localError = .errorConnOutdated
					case ConnectCloseCode.accountValidation.rawValue:
						localError = .errorConnValidation
					case ConnectCloseCode.serverTokenRefresh.rawValue:
						localError = .errorConnToken
					case ConnectCloseCode.noActivation.rawValue:
						localError = .errorConnActivation
					case ConnectCloseCode.otherLocation.rawValue:
						localError = .errorConnAccountConflict
					default:
						localError = .errorExternal
				}
			default:
				localError = .errorExternal
		}
		
		//Get if we can automatically recover from this error
		var isRecoverable = false
		if localError == .errorInternet || localError == .errorExternal {
			let isSetupMode = DispatchQueue.main.sync {
				//Run on main thread to avoid races
				(NSApplication.shared.delegate as! AppDelegate).isSetupMode
			}
			
			//Don't automatically recover if we're in setup mode
			isRecoverable = !isSetupMode
		}
		
		if isRecoverable {
			//Clear the connected clients
			connectionsLock.withWriteLock {
				connectionsMap.removeAll()
			}
			
			//Schedule the connection recovery
			startConnectionRecoveryTimer()
		}
		
		//Notify the delegate
		delegate?.dataProxy(self, didStopWithState: localError, isRecoverable: isRecoverable)
	}
	
	private func onWSReceive(data: Data) {
		do {
			var messagePacker = BytePacker(from: data)
			
			//Unpack the message type
			let messageTypeRaw = try messagePacker.unpackInt()
			guard let messageType = ConnectNHT(rawValue: messageTypeRaw) else {
				LogManager.log("Received unknown NHT \(messageTypeRaw) from Connect relay", level: .error)
				return
			}
			
			switch messageType {
				case .connectionOK:
					completeHandshake()
					
				case .serverOpen:
					let clientID = try messagePacker.unpackInt()
					addClient(clientID: clientID)
					
				case .serverClose:
					let clientID = try messagePacker.unpackInt()
					removeClient(clientID: clientID)
					
				case .serverProxy:
					let clientID = try messagePacker.unpackInt()
					
					/*
					 * App-level encryption was added at a later date,
					 * so we use a hack by checking the first byte of the message.
					 *
					 * All message types will have the first byte as 0 or -1,
					 * so we can check for other values here.
					 *
					 * If we find a match, assume that this was intentional from the client.
					 * Otherwise, backtrack and assume the client doesn't support encryption.
					 *
					 * -100 -> The content is encrypted
					 * -101 -> The content is not encrypted, but the client has encryption enabled
					 * -102 -> The client has encryption disabled
					 * Anything else -> The client does not support encryption
					 */
					
					let isSecure, isEncrypted: Bool
					let encryptionValue = try messagePacker.unpackByte()
					if encryptionValue == -100 {
						isSecure = true
						isEncrypted = true
					} else if encryptionValue == -101 {
						isSecure = false
						isEncrypted = false
					} else if encryptionValue == -102 {
						isSecure = true
						isEncrypted = false
					} else {
						LogManager.log("Received unknown encryption value: \(encryptionValue)", level: .notice)
						break
					}
					
					var payload = try messagePacker.unpackData()
					
					//Decrypt the data
					if isEncrypted {
						do {
							payload = try networkDecrypt(data: payload)
						} catch {
							LogManager.log("Failed to decrypt payload from Connect proxy: \(error)", level: .notice)
							break
						}
					}
					
					//Get the client
					let client = connectionsLock.withReadLock {
						connectionsMap[clientID]
					}
					
					//If the client couldn't be found, disconnect them
					guard let client = client else {
						LogManager.log("Received message from unknown client \(clientID) from Connect proxy", level: .notice)
						
						disconnect(clientID: clientID)
						break
					}
					
					//Notify the delegate
					delegate?.dataProxy(self, didReceive: payload, from: client, wasEncrypted: isSecure)
					
				default: break
			}
		} catch {
			LogManager.log("Failed to unpack message from Connect relay: \(error)", level: .error)
		}
	}
	
	private func onWSError(error: Error?) {
		//Ignore if we're not connected
		guard DispatchQueue.main.sync(execute: { isActive }) else { return }
		
		//Log the error
		if let error = error {
			LogManager.log("Encountered a WebSocket error: \(error)", level: .notice)
		} else {
			LogManager.log("Encountered an unknown WebSocket error", level: .notice)
		}
		
		//Disconnect
		onWSDisconnect(withCode: .normalClosure)
	}
	
	private func onWSPong() {
		//Stop the ping response timer
		stopPingResponseTimer()
	}
	
	//MARK: Message handling
	
	private func completeHandshake() {
		//Cancel the handshake timeout timer
		stopHandshakeTimer()
		
		//Reset the failed connection counter
		connectionRecoveryCount = 0;
		
		//Notify the delegate that we're connected
		delegate?.dataProxyDidStart(self)
	}
	
	private func addClient(clientID: Int32) {
		//Create the client
		let client = ClientConnection(id: clientID)
		
		//Add the client
		let connectionCount = connectionsLock.withWriteLock { () -> Int in
			connectionsMap[clientID] = client
			return connectionsMap.count
		}
		
		//Log the event
		LogManager.log("Client connected from Connect proxy (\(clientID))", level: .info)
		
		//Notify the delegate
		delegate?.dataProxy(self, didConnectClient: client, totalCount: connectionCount)
	}
	
	private func removeClient(clientID: Int32) {
		//Remove the client
		let (client, connectionCount) = connectionsLock.withWriteLock { () -> (ClientConnection?, Int) in
			let client = connectionsMap[clientID]
			connectionsMap[clientID] = nil
			return (client, connectionsMap.count)
		}
		
		//Make sure the client existed
		guard let client = client else {
			LogManager.log("Tried to deregister unknown client \(clientID) via Connect proxy", level: .info)
			return
		}
		
		//Log the event
		LogManager.log("Client disconnected from Connect proxy (\(clientID))", level: .info)
		
		//Notify the delegate
		delegate?.dataProxy(self, didDisconnectClient: client, totalCount: connectionCount)
	}
}
