//
//  DataProxyConnect.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-23.
//

import Foundation
import Starscream
import AppKit

class DataProxyConnect: DataProxy {
	weak var delegate: DataProxyDelegate?
	
	let name = "Connect"
	let requiresPersistence = false
	let supportsPushNotifications = true
	private var connectionsMap: [Int32: ClientConnection] = [:]
	var connections: Set<ClientConnection> { Set(connectionsMap.values) }
	let connectionsLock = ReadWriteLock()
	
	private let installationID: String
	private let userID: String
	private var idToken: String?
	
	private var webSocket: WebSocket?
	private var handshakeTimer: Timer?
	
	private var connectionRecoveryTimer: Timer?
	private var connectionRecoveryCount = 0
	//The max num of attempts before capping the delay time - not before giving up
	private static let connectionRecoveryCountMax = 8
	
	private let processingQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".proxy.connect.processing", qos: .utility, attributes: .concurrent)
	
	private var isActive = false
	
	init(installationID: String, userID: String, idToken: String? = nil) {
		self.installationID = installationID
		self.userID = userID
		self.idToken = idToken
	}
	
	@objc func startServer() {
		//Ignore if we're already connecting or connected
		guard !isActive else { return }
		
		//Cancel any active connection recover timers (in case the user initiated a reconnect)
		stopConnectionRecoveryTimer()
		
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
		var components = URLComponents(string: "wss://connect.airmessage.org")!
		components.queryItems = queryItems
		
		//Create the request
		var urlRequest = URLRequest(url: components.url!)
		urlRequest.addValue("app", forHTTPHeaderField: "Origin")
		
		//Create the WebSocket connection
		let socket = WebSocket(request: urlRequest)
		socket.delegate = self
		socket.callbackQueue = processingQueue
		socket.connect()
		webSocket = socket
		
		isActive = true
	}
	
	func stopServer() {
		//Ignore if we're not connected
		guard isActive, let socket = webSocket else { return }
		
		//Cancel the handshake timer
		stopHandshakeTimer()
		
		//Clear connected clients
		connectionsLock.withWriteLock {
			connectionsMap.removeAll()
		}
		NotificationNames.postUpdateConnectionCount(0)
		
		//Disconect
		socket.disconnect()
		isActive = false
		delegate?.dataProxy(self, didStopWithState: .stopped, isRecoverable: false)
	}
	
	deinit {
		//Make sure we stop the server when we go out of scope
		stopServer()
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
		socket.write(data: packer.data, completion: onSent)
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
		socket.write(data: packer.data, completion: nil)
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
		socket.write(data: packer.data, completion: nil)
		
		//Remove the client
		removeClient(clientID: clientID)
	}
	
	/**
	 Sets this proxy as registered, such that future requests will not try to re-register this server
	 */
	func setRegistered() {
		idToken = nil
	}
	
	//MARK: Handshake Timer
	
	private func startHandshakeTimer() {
		//Cancel the old timer
		handshakeTimer?.invalidate()
		
		//Create the new timer
		let timer = Timer(timeInterval: ConnectConstants.handshakeTimeout, target: self, selector: #selector(onHandshakeTimer), userInfo: nil, repeats: false)
		RunLoop.main.add(timer, forMode: .common)
		handshakeTimer = timer
	}
	
	private func stopHandshakeTimer() {
		handshakeTimer?.invalidate()
		handshakeTimer = nil
	}
	
	@objc private func onHandshakeTimer() {
		//Disconnect
		webSocket?.disconnect()
	}
	
	//MARK: Connection recovery timer
	
	private func startConnectionRecoveryTimer() {
		//Cancel the old timer
		connectionRecoveryTimer?.invalidate()
		
		//Wait an exponentially increasing wait period + a random delay
		let randomOffset: TimeInterval = Double(arc4random()) / Double(UInt32.max)
		let delay: TimeInterval = pow(2, Double(connectionRecoveryCount)) + randomOffset
		
		//Create the new timer
		let timer = Timer(timeInterval: delay, target: self, selector: #selector(startServer), userInfo: nil, repeats: false)
		RunLoop.main.add(timer, forMode: .common)
		connectionRecoveryTimer = timer
		
		//Add to the attempt counter
		if connectionRecoveryCount < DataProxyConnect.connectionRecoveryCountMax {
			connectionRecoveryCount += 1
		}
	}
	
	private func stopConnectionRecoveryTimer() {
		connectionRecoveryTimer?.invalidate()
		connectionRecoveryTimer = nil
	}
	
	//MARK: Event handling
	
	private func onWSConnect() {
		LogManager.log("Connection to Connect relay opened", level: .info)
		
		//Start the handshake timer
		startHandshakeTimer()
	}
	
	private func onWSDisconnect(reason: String, code: UInt16) {
		LogManager.log("Connection to Connect relay lost: \(code) / \(reason)", level: .info)
		
		//Cancel the handshake timer
		stopHandshakeTimer()
		
		//Update the active state
		DispatchQueue.main.async { [weak self] in
			self?.isActive = false
		}
		
		//Map the error code
		let localError: ServerState
		switch code {
			case 1006 /* Abnormal close */, CloseCode.normal.rawValue:
				localError = .errorInternet
			case CloseCode.protocolError.rawValue, CloseCode.policyViolated.rawValue:
				localError = .errorConnBadRequest
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
		
		//Get if we can automatically recover from this error
		var isRecoverable = false
		if localError == .errorInternet {
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
					} else {
						isSecure = true
						isEncrypted = false
						
						if encryptionValue != -102 {
							messagePacker.backtrack(size: UInt8.self)
						}
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
		//Log the error
		if let error = error {
			LogManager.log("Encountered a WebSocket error: \(error)", level: .notice)
		} else {
			LogManager.log("Encountered an unknown WebSocket error", level: .notice)
		}
		
		//Disconnect
		onWSDisconnect(reason: "", code: CloseCode.normal.rawValue)
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

//MARK: WebSocket Delegate

extension DataProxyConnect: WebSocketDelegate {
	func didReceive(event: WebSocketEvent, client: WebSocket) {
		switch event {
			case .connected(_): onWSConnect()
			case .disconnected(let reason, let code): onWSDisconnect(reason: reason, code: code)
			case .binary(let data): onWSReceive(data: data)
			case .error(let error): onWSError(error: error)
			default: break
		}
	}
}
