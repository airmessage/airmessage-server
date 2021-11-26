//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class ConnectionManager {
	public static let shared = ConnectionManager()
	
	private var dataProxy: DataProxy?
	private var keepaliveTimer: Timer?
	private let fileDownloadRequestMapLock = ReadWriteLock()
	private var fileDownloadRequestMap: [Int16: FileDownloadRequest] = [:]
	
	/**
	 Sets the data proxy to use for future connections.
	 Only call this function when the server isn't running.
	 */
	func setProxy(_ proxy: DataProxy) {
		proxy.delegate = self
		dataProxy = proxy
	}
	
	/**
	 Starts the server
	 */
	func start() {
		guard let proxy = dataProxy else {
			LogManager.log("Tried to start connection manager, but no proxy is assigned", level: .error)
			NotificationNames.postUpdateUIState(ServerState.stopped)
			return
		}
		
		//Emit an update
		NotificationNames.postUpdateUIState(ServerState.starting)
		
		//Start the proxy
		proxy.startServer()
	}
	
	/**
	 Stops the server
	 */
	func stop() {
		//Stop the proxy
		dataProxy?.stopServer()
	}
	
	//MARK: Timers
	
	@objc private func runKeepalive() {
		guard let dataProxy = dataProxy else { return }
		
		//Send a ping to all clients
		ConnectionManager.sendMessageHeaderOnly(dataProxy, to: nil, ofType: NHT.ping, encrypt: false)
		
		//Start ping response timers
		dataProxy.connectionsLock.withReadLock {
			for connection in dataProxy.connections {
				connection.startTimer(ofType: .pingExpiry, interval: CommConst.pingTimeout) { [weak self] client in
					self?.dataProxy?.disconnect(client: client)
				}
			}
		}
	}
	
	//MARK: Send helpers
	
	/**
	 Packs and sends a header-only message to a client
	 */
	private static func sendMessageHeaderOnly(_ dataProxy: DataProxy, to client: C?, ofType type: NHT, encrypt: Bool) {
		var packer = AirPacker(capacity: MemoryLayout<Int32>.size)
		packer.pack(int: type.rawValue)
		dataProxy.send(message: packer.data, to: client, encrypt: encrypt, onSent: nil)
	}
	
	/**
	 Cleanly disconnects a client, sending a message beforehand
	 */
	private static func sendInitiateClose(_ dataProxy: DataProxy, to client: C) {
		var packer = AirPacker(capacity: MemoryLayout<Int32>.size)
		packer.pack(int: NHT.close.rawValue)
		dataProxy.send(message: packer.data, to: client, encrypt: false) { [weak dataProxy] in
			dataProxy?.disconnect(client: client)
		}
	}
	
	/**
	 Notifies a client that an attachment request failed with a code
	 */
	private static func sendAttachmentReqFail(_ dataProxy: DataProxy, to client: C, withReqID reqID: Int16, withCode code: NSTAttachmentRequest) {
		var packer = AirPacker(capacity: MemoryLayout<Int16>.size + MemoryLayout<Int32>.size * 3)
		packer.pack(int: NHT.attachmentReqFail.rawValue)
		packer.pack(short: reqID)
		packer.pack(int: code.rawValue)
		dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
	}
	
	//MARK: Send functions
	
	/**
	 Sends an ID update to a client
	 */
	public func send(idUpdate id: Int64, to client: C?) {
		guard let dataProxy = dataProxy else { return }
		
		var packer = AirPacker(capacity: MemoryLayout<Int32>.size + MemoryLayout<Int64>.size)
		packer.pack(int: NHT.idUpdate.rawValue)
		packer.pack(long: id)
		
		dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
	}
	
	/**
	 Sends an array of messages
	 */
	public func send(messageUpdate messages: [ConversationItem], to client: C? = nil, withCode responseCode: NHT = .messageUpdate) {
		guard let dataProxy = dataProxy else { return }
		
		var packer = AirPacker()
		packer.pack(int: responseCode.rawValue)
		packer.pack(packableArray: messages)
		
		dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
	}
	
	/**
	 Sends an array of modifiers as a modifier update to all connected clients
	 */
	public func send(modifierUpdate modifiers: [ModifierInfo], to client: C? = nil) {
		guard let dataProxy = dataProxy else { return }
		
		var packer = AirPacker()
		packer.pack(int: NHT.modifierUpdate.rawValue)
		packer.pack(packableArray: modifiers)
		
		dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
	}
	
	/**
	 Sends a common response message to a client
	 */
	public func send(basicResponseOfCode code: NHT, requestID: Int16, resultCode: Int32, details: String? = nil, to client: C) {
		guard let dataProxy = dataProxy else { return }
		
		var packer = AirPacker()
		packer.pack(int: code.rawValue)
		packer.pack(short: requestID)
		packer.pack(int: resultCode)
		packer.pack(optionalString: details)
		
		dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
	}
	
	/**
	 Sends an array of incoming messages or incoming modifiers as a push notification
	 */
	public func sendPushNotification(messages: [MessageInfo], modifiers: [ModifierInfo]) {
		//Make sure we have content to send
		guard !messages.isEmpty || !modifiers.isEmpty else { return }
		
		//Make sure we have an active data proxy
		guard let dataProxy = dataProxy, dataProxy.supportsPushNotifications else { return }
		
		//Serialize the data
		var securePacker = AirPacker()
		securePacker.pack(packableArray: messages)
		securePacker.pack(packableArray: modifiers)
		
		//Encrypt the data
		let payload: Data
		let password = PreferencesManager.shared.password
		let encrypt = !password.isEmpty
		if encrypt {
			do {
				payload = try networkEncrypt(data: securePacker.data)
			} catch {
				LogManager.log("Failed to encrypt data for push notification: \(error)", level: .error)
				return
			}
		} else {
			payload = securePacker.data
		}
		
		//Pack into a final message and send
		var messagePacker = AirPacker()
		messagePacker.pack(bool: encrypt)
		messagePacker.pack(payload: payload)
		dataProxy.send(pushNotification: messagePacker.data, version: 2)
	}
	
	//MARK: Handle message
	
	private func handleMessageAuthentication(dataProxy: DataProxy, packer messagePacker: inout AirPacker, from client: C) throws {
		//Cancel the handshake expiry timer
		client.cancelTimer(ofType: .handshakeExpiry)
		
		//Sends an authorization rejected message and closes the connection
		func rejectAuthorization(with code: NSTAuth) {
			var responsePacker = AirPacker(capacity: MemoryLayout<Int32>.size * 2)
			responsePacker.pack(int: NHT.authentication.rawValue)
			responsePacker.pack(int: code.rawValue)
			dataProxy.send(message: responsePacker.data, to: client, encrypt: false) { [weak dataProxy] in
				dataProxy?.disconnect(client: client)
			}
		}
		
		let clientRegistration: ClientConnection.Registration
		if dataProxy.requiresAuthentication {
			//Reading the data
			let encryptedPayload = try messagePacker.unpackPayload()
			let transmissionCheck: Data
			do {
				let decryptedPayload = try networkDecrypt(data: encryptedPayload)
				var securePacker = AirPacker(from: decryptedPayload)
				
				transmissionCheck = try securePacker.unpackPayload()
				let installationID = try securePacker.unpackString()
				let clientName = try securePacker.unpackString()
				let platformID = try securePacker.unpackString()
				clientRegistration = ClientConnection.Registration(installationID: installationID, clientName: clientName, platformID: platformID)
			} catch {
				//Logging the error
				LogManager.log("Failed to decrypt authentication payload: \(error)", level: .info)
				
				//Sending a message and closing the connection
				rejectAuthorization(with: .unauthorized)
				return
			}
			
			//Checking the transmission check
			guard transmissionCheck == client.transmissionCheck else {
				rejectAuthorization(with: .unauthorized)
				return
			}
			client.transmissionCheck = nil
		} else {
			//Reading the data plainly
			let installationID = try messagePacker.unpackString()
			let clientName = try messagePacker.unpackString()
			let platformID = try messagePacker.unpackString()
			clientRegistration = ClientConnection.Registration(installationID: installationID, clientName: clientName, platformID: platformID)
		}
		
		//Disconnecting clients with the same installation ID
		let existingClientSet = dataProxy.connectionsLock.withReadLock {
			dataProxy.connections.filter { existingClient in existingClient.registration?.installationID == clientRegistration.installationID }
		}
		for existingClient in existingClientSet {
			ConnectionManager.sendInitiateClose(dataProxy, to: existingClient)
		}
		
		//Setting the client registration
		client.registration = clientRegistration
		
		//Sending a response message
		var responsePacker = AirPacker()
		responsePacker.pack(int: NHT.authentication.rawValue)
		responsePacker.pack(int: NSTAuth.ok.rawValue)
		responsePacker.pack(string: PreferencesManager.shared.installationID) //Installation ID
		responsePacker.pack(string: getComputerName() ?? "Unknown") //Computer name
		responsePacker.pack(string: ProcessInfo.processInfo.operatingSystemVersionString) //System version
		responsePacker.pack(string: Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String) //Software version
		dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
		
		//Sending the client the latest database entry ID
		if let lastID = DatabaseManager.shared.lastScannedMessageID {
			send(idUpdate: lastID, to: client)
		}
	}
	
	private func handleMessageTimeRetrieval(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let timeLower = try messagePacker.unpackLong()
		let timeUpper = try messagePacker.unpackLong()
		
		//Execute the request
		let resultGrouping: DBFetchGrouping
		let resultActivityUpdates: [ActivityStatusModifierInfo]
		do {
			resultGrouping = try DatabaseManager.shared.fetchGrouping(fromTime: timeLower, to: timeUpper)
			resultActivityUpdates = try DatabaseManager.shared.fetchActivityStatus(fromTime: timeLower)
		} catch {
			LogManager.log("Failed to fetch messages for time range \(timeLower) - \(timeUpper): \(error)", level: .notice)
			return
		}
		
		//Send responses
		if !resultGrouping.conversationItems.isEmpty {
			send(messageUpdate: resultGrouping.conversationItems, to: client)
		}
		
		let resultModifiers: [ModifierInfo] = resultGrouping.looseModifiers + resultActivityUpdates
		if !resultModifiers.isEmpty {
			send(modifierUpdate: resultModifiers, to: client)
		}
	}
	
	private func handleMessageIDRetrieval(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let idLower = try messagePacker.unpackLong()
		let timeLower = try messagePacker.unpackLong()
		
		//Execute the request
		let resultGrouping: DBFetchGrouping
		let resultActivityUpdates: [ActivityStatusModifierInfo]
		do {
			resultGrouping = try DatabaseManager.shared.fetchGrouping(fromID: idLower)
			resultActivityUpdates = try DatabaseManager.shared.fetchActivityStatus(fromTime: timeLower)
		} catch {
			LogManager.log("Failed to fetch messages for ID range >\(idLower): \(error)", level: .notice)
			return
		}
		
		//Send responses
		if !resultGrouping.conversationItems.isEmpty {
			send(messageUpdate: resultGrouping.conversationItems, to: client)
		}
		
		let resultModifiers: [ModifierInfo] = resultGrouping.looseModifiers + resultActivityUpdates
		if !resultModifiers.isEmpty {
			send(modifierUpdate: resultModifiers, to: client)
		}
	}
	
	private func handleMessageMassRetrieval(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request ID
		let requestID = try messagePacker.unpackShort()
		
		//Should we filter messages by date?
		let timeSinceMessages: Int64? = try messagePacker.unpackBool() ? messagePacker.unpackLong() : nil
		
		//Should we download attachments?
		let downloadAttachments = try messagePacker.unpackBool()
		let attachmentsFilter: AdvancedAttachmentsFilter?
		if downloadAttachments {
			//Should we filter attachments by date?
			let timeSinceAttachments: Int64? = try messagePacker.unpackBool() ? messagePacker.unpackLong() : nil
			
			//Should we filter attachments by size?
			let sizeLimitAttachments: Int64? = try messagePacker.unpackBool() ? messagePacker.unpackLong() : nil
			
			//What types of attachments should we download?
			let attachmentsWhitelist = try messagePacker.unpackStringArray() //If it's on the whitelist, download it
			let attachmentsBlacklist = try messagePacker.unpackStringArray() //If it's on the blacklist, skip it
			let attachmentsDownloadOther = try messagePacker.unpackBool() //If it's on neither list, download if if this value is true
			
			attachmentsFilter = AdvancedAttachmentsFilter(
				timeSince: timeSinceAttachments,
				maxSize: sizeLimitAttachments,
				whitelist: attachmentsWhitelist,
				blacklist: attachmentsBlacklist,
				downloadExceptions: attachmentsDownloadOther
			)
		} else {
			attachmentsFilter = nil
		}
		
		//Fetch conversations from the database
		let resultConversations: [BaseConversationInfo]
		let messageCount: Int
		do {
			resultConversations = try DatabaseManager.shared.fetchConversationArray(since: timeSinceMessages)
			messageCount = Int(try DatabaseManager.shared.countMessages(since: timeSinceMessages))
		} catch {
			LogManager.log("Failed to read conversations from database: \(error)", level: .error)
			return
		}
		
		//Make sure the client is still connected
		guard client.isConnected.value else { return }
		
		//Send the initial mass retrieval info
		do {
			guard let dataProxy = dataProxy else { return }
			
			var responsePacker = AirPacker()
			responsePacker.pack(int: NHT.massRetrieval.rawValue)
			
			responsePacker.pack(short: requestID)
			responsePacker.pack(int: 0) //Response index
			
			responsePacker.pack(packableArray: resultConversations)
			responsePacker.pack(int: Int32(messageCount))
			
			dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
		}
		
		var messageIterator = try DatabaseManager.shared.fetchMessagesLazy(since: timeSinceMessages).makeIterator()
		var messageResponseIndex: Int32 = 1
		var previousLooseModifiers: [ModifierInfo] = []
		while true {
			//Get next 20 results
			let groupArray: [DatabaseManager.FailableDatabaseMessageRow] = (0..<20).compactMap { i in messageIterator.next() }
			
			//Break if we're done
			if groupArray.isEmpty {
				break
			}
			
			//Check for errors
			guard !groupArray.contains(where: { $0.isError }) else {
				return
			}
			
			//Group the results
			var (conversationItems, looseModifiers) = DatabaseConverter.groupMessageRows(groupArray.map { $0.row }).destructured
			
			//Apply loose modifiers from prevous groups
			for (i, modifier) in previousLooseModifiers.enumerated().reversed() {
				if let conversationItemIndex = conversationItems.lastIndex(where: { $0.guid == modifier.messageGUID }) {
					let conversationItem = conversationItems[conversationItemIndex]
					
					//Make sure the conversation item is a message
					guard var message = conversationItem as? MessageInfo else { continue }
					
					//Add the modifier to the message
					if let tapback = modifier as? TapbackModifierInfo {
						message.tapbacks.append(tapback)
					} else if let sticker = modifier as? StickerModifierInfo {
						message.stickers.append(sticker)
					}
					conversationItems[conversationItemIndex] = message
					
					//Remove the modifier from the array
					previousLooseModifiers.remove(at: i)
				}
			}
			
			//Keep track of all new loose modifiers
			previousLooseModifiers += looseModifiers
			
			//Make sure we're still connected
			guard client.isConnected.value else { return }
			
			//Send the results
			do {
				guard let dataProxy = dataProxy else { return }
				
				var packer = AirPacker()
				packer.pack(int: NHT.massRetrieval.rawValue)
				
				packer.pack(short: requestID)
				packer.pack(int: messageResponseIndex)
				
				packer.pack(packableArray: conversationItems)
				
				dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
			}
			
			//Assemble and filter attachments
			let messageAttachments = conversationItems
				.compactMap { $0 as? MessageInfo }
				.flatMap { message in
					message.attachments.filter { attachment in
						attachmentsFilter?.apply(to: attachment, ofDate: message.date) ?? true
					}
				}
			for attachment in messageAttachments {
				//Make sure the file exists
				guard let attachmentURL = attachment.localURL,
					  FileManager.default.fileExists(atPath: attachmentURL.path) else {
					continue
				}
				
				//Try to normalize the file
				let fileURL: URL
				let fileType: String?
				let fileName: String
				let fileNeedsCleanup: Bool
				if let normalizedDetails = normalizeFile(url: attachmentURL, ext: attachmentURL.pathExtension) {
					fileURL = normalizedDetails.url
					fileType = normalizedDetails.type
					fileName = normalizedDetails.name
					fileNeedsCleanup = true
				} else {
					fileURL = attachmentURL
					fileType = attachment.type
					fileName = attachment.name
					fileNeedsCleanup = false
				}
				
				//Clean up
				defer {
					if fileNeedsCleanup {
						try? FileManager.default.removeItem(at: fileURL)
					}
				}
				
				//Read the file
				var fileResponseIndex: Int32 = 0
				do {
					let compressionPipe = try CompressionPipeDeflate(chunkSize: Int(CommConst.defaultFileChunkSize))
					
					let fileHandle = try FileHandle(forReadingFrom: fileURL)
					
					var doBreak: Bool
					repeat {
						doBreak = try autoreleasepool {
							//Read data
							var data = try fileHandle.readCompat(upToCount: Int(CommConst.defaultFileChunkSize))
							let isEOF = data.count == 0
							
							//Compress the data
							let dataOut = try compressionPipe.pipe(data: &data, isLast: isEOF)
							
							//Make sure the client is still connected
							guard client.isConnected.value else { return true }
							
							//Build and send the request
							do {
								guard let dataProxy = dataProxy else { return true }
								
								var packer = AirPacker()
								packer.pack(int: NHT.massRetrievalFile.rawValue)
								
								packer.pack(short: requestID)
								packer.pack(int: fileResponseIndex)
								
								//Include extra information with the initial response
								if fileResponseIndex == 0 {
									packer.pack(string: attachment.name) //Original file name
									packer.pack(optionalString: fileName) //Converted file name
									packer.pack(optionalString: fileType) //Converted file type
								}
								
								packer.pack(bool: isEOF) //Is last message
								
								packer.pack(string: attachment.guid) //Attachment GUID
								packer.pack(payload: dataOut) //Data
								
								dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
							}
							
							fileResponseIndex += 1
							
							//Break if we reached the end of the file
							return isEOF
						}
					} while !doBreak
				} catch {
					LogManager.log("Failed to read / compress data for mass retrieval attachment file \(fileURL.path) (\(attachment.guid)): \(error)", level: .notice)
					return
				}
			
				messageResponseIndex += 1
			}
		}
		
		//Send a success message
		guard let dataProxy = dataProxy else { return }
		ConnectionManager.sendMessageHeaderOnly(dataProxy, to: client, ofType: NHT.massRetrievalFinish, encrypt: true)
	}
	
	private func handleMessageConversationUpdate(packer messagePacker: inout AirPacker, from client: C) throws {
		let chatGUIDArray = try messagePacker.unpackStringArray()
		
		//Fetch conversations from the database
		let resultConversations: [BaseConversationInfo]
		do {
			resultConversations = try DatabaseManager.shared.fetchConversationArray(in: chatGUIDArray)
		} catch {
			LogManager.log("Failed to read conversations from database: \(error)", level: .error)
			return
		}
		
		//Send a response
		guard let dataProxy = dataProxy else { return }
		
		var responsePacker = AirPacker()
		responsePacker.pack(int: NHT.conversationUpdate.rawValue)
		responsePacker.pack(packableArray: resultConversations)
		
		dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
	}
	
	private func handleMessageAttachmentRequest(packer messagePacker: inout AirPacker, from client: C) throws {
		let requestID = try messagePacker.unpackShort() //The request ID to avoid collisions
		let chunkSize = try messagePacker.unpackInt() //How many bytes to upload per packet
		let attachmentGUID = try messagePacker.unpackString() //The GUID of the attachment file to download
		
		//Send an acknowledgement
		do {
			guard let dataProxy = dataProxy else { return }
			
			var responsePacker = AirPacker()
			responsePacker.pack(int: NHT.attachmentReqConfirm.rawValue)
			responsePacker.pack(short: requestID)
			
			dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
		}
		
		//Get the file from the database
		let fileDetails: DatabaseManager.AttachmentFile?
		do {
			fileDetails = try DatabaseManager.shared.fetchFile(fromAttachmentGUID: attachmentGUID)
		} catch {
			LogManager.log("Failed to get file path for attachment GUID \(attachmentGUID)): \(error)", level: .notice)
			
			//Send a response (I/O error)
			guard let dataProxy = dataProxy else { return }
			ConnectionManager.sendAttachmentReqFail(dataProxy, to: client, withReqID: requestID, withCode: .io)
			return
		}
		
		//Check if the entry was found
		guard let fileDetails = fileDetails else {
			//Send a response (not found)
			guard let dataProxy = dataProxy else { return }
			ConnectionManager.sendAttachmentReqFail(dataProxy, to: client, withReqID: requestID, withCode: .notFound)
			return
		}
		
		//Check if the file exists
		guard FileManager.default.fileExists(atPath: fileDetails.url.path) else {
			//Send a response (not saved)
			guard let dataProxy = dataProxy else { return }
			ConnectionManager.sendAttachmentReqFail(dataProxy, to: client, withReqID: requestID, withCode: .notSaved)
			return
		}
		
		//Try to normalize the file
		let fileURL: URL
		let fileType: String?
		let fileName: String
		let fileNeedsCleanup: Bool
		if let normalizedDetails = normalizeFile(url: fileDetails.url, ext: fileDetails.url.pathExtension) {
			fileURL = normalizedDetails.url
			fileType = normalizedDetails.type
			fileName = normalizedDetails.name
			fileNeedsCleanup = true
		} else {
			fileURL = fileDetails.url
			fileType = fileDetails.type
			fileName = fileDetails.name
			fileNeedsCleanup = false
		}
		
		//Clean up
		defer {
			if fileNeedsCleanup {
				try? FileManager.default.removeItem(at: fileURL)
			}
		}
		
		//Check to make sure the client is still connected
		guard client.isConnected.value else { return }
		
		//Get the file size
		let fileSize: Int64
		do {
			let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
			fileSize = Int64(resourceValues.fileSize!)
		} catch {
			LogManager.log("Failed to get file size for attachment file \(fileURL.path) (\(attachmentGUID)): \(error)", level: .notice)
			
			//Send a response (I/O)
			guard let dataProxy = dataProxy else { return }
			ConnectionManager.sendAttachmentReqFail(dataProxy, to: client, withReqID: requestID, withCode: .io)
			return
		}
		
		//Read the file
		var responseIndex: Int32 = 0
		do {
			let compressionPipe = try CompressionPipeDeflate(chunkSize: Int(chunkSize))
			
			let fileHandle = try FileHandle(forReadingFrom: fileURL)
			
			var doBreak: Bool
			repeat {
				doBreak = try autoreleasepool {
					//Read data
					var data = try fileHandle.readCompat(upToCount: Int(chunkSize))
					let isEOF = data.count == 0
					
					//Compress the data
					let dataOut = try compressionPipe.pipe(data: &data, isLast: isEOF)
					
					//Make sure the client is still connected
					guard client.isConnected.value else { return true }
					
					//Build and send the request
					do {
						guard let dataProxy = dataProxy else { return true }
						
						var packer = AirPacker()
						packer.pack(int: NHT.attachmentReq.rawValue)
						
						packer.pack(short: requestID)
						packer.pack(int: responseIndex)
						
						//Include extra information with the initial response
						if responseIndex == 0 {
							packer.pack(optionalString: fileName)
							packer.pack(optionalString: fileType)
							packer.pack(long: fileSize)
						}
						
						packer.pack(bool: isEOF) //Is last message
						
						packer.pack(payload: dataOut)
						
						dataProxy.send(message: packer.data, to: client, encrypt: true, onSent: nil)
					}
					
					responseIndex += 1
					
					//Break if we reached the end of the file
					return isEOF
				}
			} while !doBreak
		} catch {
			LogManager.log("Failed to read / compress data for attachment file \(fileURL.path) (\(attachmentGUID)): \(error)", level: .notice)
			
			//Make sure the client is still connected
			guard client.isConnected.value else { return }
			
			//Send an error
			guard let dataProxy = dataProxy else { return }
			ConnectionManager.sendAttachmentReqFail(dataProxy, to: client, withReqID: requestID, withCode: .io)
			return
		}
	}
	
	private func handleMessageLiteConversationRetrieval(packer messagePacker: inout AirPacker, from client: C) throws {
		//Fetch the conversations
		let conversations: [LiteConversationInfo]
		do {
			conversations = try DatabaseManager.shared.fetchLiteConversations()
		} catch {
			LogManager.log("Failed to fetch lite conversation summary: \(error)", level: .error)
			return
		}
		
		guard let dataProxy = dataProxy else { return }
		
		//Send the response
		var responsePacker = AirPacker()
		responsePacker.pack(int: NHT.liteConversationRetrieval.rawValue)
		responsePacker.pack(packableArray: conversations)
		
		dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
	}
	
	private func handleMessageLiteThreadRetrieval(packer messagePacker: inout AirPacker, from client: C) throws {
		let chatGUID = try messagePacker.unpackString() //The GUID of the chat to query
		let firstMessageID: Int64? = try messagePacker.unpackBool() ? try messagePacker.unpackLong() : nil //The last message ID the client has, send messages earlier than this
		
		//Fetch messages from the database
		let messages: [ConversationItem]
		do {
			messages = try DatabaseManager.shared.fetchLiteThread(chatGUID: chatGUID, before: firstMessageID)
		} catch {
			LogManager.log("Failed to fetch lite thread messages for \(chatGUID) before \(firstMessageID.map{ String($0) } ?? "nil"): \(error)", level: .error)
			return
		}
		
		guard let dataProxy = dataProxy else { return }
		
		//Send a response
		var responsePacker = AirPacker()
		responsePacker.pack(int: NHT.liteThreadRetrieval.rawValue)
		responsePacker.pack(string: chatGUID)
		if let firstMessageID = firstMessageID {
			responsePacker.pack(bool: true)
			responsePacker.pack(long: firstMessageID)
		} else {
			responsePacker.pack(bool: false)
		}
		responsePacker.pack(packableArray: messages.reversed()) //Send messages least recent to most recent
		
		dataProxy.send(message: responsePacker.data, to: client, encrypt: true, onSent: nil)
	}
	
	private func handleMessageCreateChat(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let requestID = try messagePacker.unpackShort() //The request ID to keep track of requests
		let chatMembers = try messagePacker.unpackStringArray() //The members of this conversation
		let chatService = try messagePacker.unpackString() //The service of this conversation
		
		//Create the chat
		let chatID: String
		do {
			chatID = try MessageManager.createChat(withAddresses: chatMembers, service: chatService)
		} catch {
			if let error = error as? AppleScriptExecutionError {
				let nstCode: NSTCreateChat
				switch error.code {
					case AppleScriptCodes.errorUnauthorized:
						nstCode = .unauthorized
					default:
						nstCode = .scriptError
				}
				
				send(basicResponseOfCode: .createChat, requestID: requestID, resultCode: nstCode.rawValue, details: error.message, to: client)
			} else if let error = error as? ForwardsSupportError {
				send(basicResponseOfCode: .createChat, requestID: requestID, resultCode: NSTCreateChat.scriptError.rawValue, details: error.errorDescription, to: client)
			}
			
			return
		}
		
		//Send a response
		send(basicResponseOfCode: .createChat, requestID: requestID, resultCode: NSTCreateChat.ok.rawValue, details: chatID, to: client)
	}
	
	/**
	 Handles the common case of running a failable operation in response to an outgoing message request
	 */
	private func handleMessageSendCommon(requestID: Int16, client: C, action: () throws -> Void) {
		//Send the message
		do {
			try action()
		} catch {
			if let error = error as? AppleScriptExecutionError {
				let nstCode: NSTSendResult
				switch error.code {
					case AppleScriptCodes.errorUnauthorized:
						nstCode = .unauthorized
					case AppleScriptCodes.errorNoChat:
						nstCode = .noConversation
					default:
						nstCode = .scriptError
				}
				
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: nstCode.rawValue, details: error.message, to: client)
			} else if let error = error as? ForwardsSupportError {
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.scriptError.rawValue, details: error.errorDescription, to: client)
			}
			
			return
		}
		
		//Send a response
		send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.ok.rawValue, details: nil, to: client)
	}
	
	private func handleMessageSendTextExisting(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let requestID = try messagePacker.unpackShort() //The request ID to keep track of requests
		let chatGUID = try messagePacker.unpackString() //The GUID of the chat to send a message to
		let message = try messagePacker.unpackString() //The message to send
		
		//Send the message
		handleMessageSendCommon(requestID: requestID, client: client) {
			try MessageManager.send(message: message, toExistingChat: chatGUID)
		}
	}
	
	private func handleMessageSendTextNew(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let requestID = try messagePacker.unpackShort() //The request ID to keep track of requests
		let members = try messagePacker.unpackStringArray() //The members of the chat to send the message to
		let service = try messagePacker.unpackString(); //The service of the chat
		let message = try messagePacker.unpackString() //The message to send
		
		//Send the message
		handleMessageSendCommon(requestID: requestID, client: client) {
			try MessageManager.send(message: message, toNewChat: members, onService: service)
		}
	}
	
	private enum DownloadRequestCreateError: Error {
		case alreadyExists
		case createError(Error)
	}
	
	private func handleMessageFileDownloadCommon(client: C, requestID: Int16, packetIndex: Int32, fileName: String?, fileData: inout Data, isLast: Bool, customData: Any, onComplete: (FileDownloadRequest) throws -> Void) throws {
		let downloadRequest: FileDownloadRequest
		if packetIndex == 0 {
			do {
				downloadRequest = try fileDownloadRequestMapLock.withWriteLock { () throws -> FileDownloadRequest in
					//Make sure we don't have a matching request
					guard fileDownloadRequestMap[requestID] == nil else {
						throw DownloadRequestCreateError.alreadyExists
					}
					
					//Create a new request
					let downloadRequest: FileDownloadRequest
					do {
						downloadRequest = try FileDownloadRequest(fileName: fileName!, requestID: requestID, customData: customData)
					} catch {
						throw DownloadRequestCreateError.createError(error)
					}
					
					//Set the request
					fileDownloadRequestMap[requestID] = downloadRequest
					
					return downloadRequest
				}
				
				//Add the data
				do {
					try downloadRequest.append(&fileData)
				} catch {
					LogManager.log("Failed to write download request initial file data: \(error)", level: .notice)
					send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.internalError.rawValue, details: "Failed to write initial file data: \(error.localizedDescription)", to: client)
					return
				}
				
				//Set the timer callback
				downloadRequest.timeoutCallback = { [weak self, weak client] in
					DispatchQueue.global(qos: .default).async { [weak self, weak client] in
						//Clean up leftover files
						try? downloadRequest.cleanUp()
						
						//Clean up task reference
						guard let self = self else { return }
						self.fileDownloadRequestMapLock.withWriteLock {
							self.fileDownloadRequestMap[requestID] = nil
						}
						
						//Send a message to the client
						guard let client = client, client.isConnected.value else { return }
						self.send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.requestTimeout.rawValue, details: nil, to: client)
					}
				}
			} catch DownloadRequestCreateError.alreadyExists {
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.badRequest.rawValue, details: "Request ID \(requestID) already exists", to: client)
				return
			} catch DownloadRequestCreateError.createError(let createError) {
				LogManager.log("Failed to create file download request: \(createError)", level: .error)
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.internalError.rawValue, details: "Failed to create file download request: \(createError.localizedDescription)", to: client)
				return
			}
		} else {
			//Find the request
			guard let downloadRequestFromMap = fileDownloadRequestMapLock.withReadLock({ fileDownloadRequestMap[requestID] }) else {
				return
			}
			downloadRequest = downloadRequestFromMap
			
			//Stop the timeout timer
			downloadRequest.stopTimeoutTimer()
			
			//Make sure we can still accept new data
			guard !downloadRequest.isDataComplete else {
				LogManager.log("Received additional data for file download request \(requestID)-\(packetIndex), even though data is already complete", level: .notice)
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.badRequest.rawValue, details: "Data is already complete", to: client)
				return
			}
			
			//Make sure we're on the right packet index
			guard downloadRequest.packetsWritten == packetIndex else {
				LogManager.log("Received invalid packet order for file download request \(requestID)-\(packetIndex); expected \(downloadRequest.packetsWritten)", level: .notice)
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.badRequest.rawValue, details: "Received invalid packet order for file download request \(requestID)-\(packetIndex); expected \(downloadRequest.packetsWritten)", to: client)
				return
			}
			
			//Add the data
			do {
				try downloadRequest.append(&fileData)
			} catch {
				LogManager.log("Failed to write download request file data for request \(requestID)-\(packetIndex): \(error)", level: .notice)
				send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.internalError.rawValue, details: "Failed to write file data for packet index \(packetIndex): \(error.localizedDescription)", to: client)
				return
			}
		}
		
		//Check if there are still more packets to come
		if !isLast {
			//Start the timeout timer
			downloadRequest.startTimeoutTimer()
			return
		}
		
		//Make sure we have complete data
		guard downloadRequest.isDataComplete else {
			LogManager.log("Data for file download request \(requestID)-\(packetIndex) is not complete, but client declared as such", level: .notice)
			send(basicResponseOfCode: .sendResult, requestID: requestID, resultCode: NSTSendResult.badRequest.rawValue, details: "Data is not complete, but client stopped sending data", to: client)
			return
		}
		
		//Handle the data
		try onComplete(downloadRequest)
	}
	
	private func handleMessageSendFileExisting(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let requestID = try messagePacker.unpackShort() //The request ID to keep track of requests
		let packetIndex = try messagePacker.unpackInt() //The index of this packet, to ensure that packets are received and written in order
		let isLast = try messagePacker.unpackBool() //Is this the last packet?
		let chatGUID = try messagePacker.unpackString() //The GUID of the chat to send the message to
		var fileData = try messagePacker.unpackPayload() //The compressed file data to append
		let fileName = packetIndex == 0 ? try messagePacker.unpackString() : nil //The name of the file to download and send
		
		try handleMessageFileDownloadCommon(client: client, requestID: requestID, packetIndex: packetIndex, fileName: fileName, fileData: &fileData, isLast: isLast, customData: chatGUID) { downloadRequest in
			handleMessageSendCommon(requestID: requestID, client: client) {
				try MessageManager.send(file: downloadRequest.fileURL, toExistingChat: downloadRequest.customData as! String)
			}
		}
	}
	
	private func handleMessageSendFileNew(packer messagePacker: inout AirPacker, from client: C) throws {
		//Read the request
		let requestID = try messagePacker.unpackShort() //The request ID to keep track of requests
		let packetIndex = try messagePacker.unpackInt() //The index of this packet, to ensure that packets are received and written in order
		let isLast = try messagePacker.unpackBool() //Is this the last packet?
		let members = try messagePacker.unpackStringArray() //The members of the chat to send the message to
		var fileData = try messagePacker.unpackPayload() //The compressed file data to append
		let fileName = packetIndex == 0 ? try messagePacker.unpackString() : nil //The name of the file to download and send
		let service = packetIndex == 0 ? try messagePacker.unpackString() : nil //The service of the conversation
		
		try handleMessageFileDownloadCommon(client: client, requestID: requestID, packetIndex: packetIndex, fileName: fileName, fileData: &fileData, isLast: isLast, customData: (members, service)) { downloadRequest in
			handleMessageSendCommon(requestID: requestID, client: client) {
				let (members, service) = downloadRequest.customData as! ([String], String)
				try MessageManager.send(file: downloadRequest.fileURL, toNewChat: members, onService: service)
			}
		}
	}
	
	//MARK: Process message
	
	@discardableResult
	private func processMessageStandard(dataProxy: DataProxy, packer: inout AirPacker, from client: C, type: NHT) throws -> Bool {
		switch type {
			case .close:
				dataProxy.disconnect(client: client)
			case .ping:
				ConnectionManager.sendMessageHeaderOnly(dataProxy, to: client, ofType: NHT.pong, encrypt: false)
			case .authentication:
				try handleMessageAuthentication(dataProxy: dataProxy, packer: &packer, from: client)
			default:
				return false
		}
		
		return true
	}
	
	@discardableResult
	private func processMessageSensitive(dataProxy: DataProxy, packer: inout AirPacker, from client: C, type: NHT) throws -> Bool {
		//Process non-standard messages first
		if try processMessageStandard(dataProxy: dataProxy, packer: &packer, from: client, type: type) {
			return true
		}
		
		//The client can't perform any sensitive tasks unless they are authenticated
		guard client.registration != nil else {
			return false
		}
		
		switch type {
			case .timeRetrieval: try handleMessageTimeRetrieval(packer: &packer, from: client)
			case .idRetrieval: try handleMessageIDRetrieval(packer: &packer, from: client)
			case .massRetrieval: try handleMessageMassRetrieval(packer: &packer, from: client)
			case .conversationUpdate: try handleMessageConversationUpdate(packer: &packer, from: client)
			case .attachmentReq: try handleMessageAttachmentRequest(packer: &packer, from: client)
				
			case .liteConversationRetrieval: try handleMessageLiteConversationRetrieval(packer: &packer, from: client)
			case .liteThreadRetrieval: try handleMessageLiteThreadRetrieval(packer: &packer, from: client)
			
			case .createChat: try handleMessageCreateChat(packer: &packer, from: client)
			case .sendTextExisting: try handleMessageSendTextExisting(packer: &packer, from: client)
			case .sendTextNew: try handleMessageSendTextNew(packer: &packer, from: client)
			case .sendFileExisting: try handleMessageSendFileExisting(packer: &packer, from: client)
			case .sendFileNew: try handleMessageSendFileNew(packer: &packer, from: client)
			
			default: return false
		}
		
		return true
	}
}

//MARK: Data proxy delegate

extension ConnectionManager: DataProxyDelegate {
	func dataProxyDidStart(_ dataProxy: DataProxy) {
		//Emit an update
		NotificationNames.postUpdateUIState(ServerState.running)
		
		//Start the keepalive timer
		if dataProxy.requiresPersistence {
			let timer = Timer(timeInterval: CommConst.keepAliveMillis, target: self, selector: #selector(runKeepalive), userInfo: nil, repeats: true)
			RunLoop.main.add(timer, forMode: .common)
			keepaliveTimer = timer
		}
		
		LogManager.log("Server started", level: .info)
	}
	
	func dataProxy(_ dataProxy: DataProxy, didStopWithState state: ServerState, isRecoverable: Bool) {
		//Emit an update
		NotificationNames.postUpdateUIState(state)
		
		//Stop the keepalive timer
		keepaliveTimer?.invalidate()
		keepaliveTimer = nil
		
		if isRecoverable {
			LogManager.log("Server paused", level: .info)
		} else {
			LogManager.log("Server stopped", level: .info)
		}
	}
	
	func dataProxy(_ dataProxy: DataProxy, didConnectClient client: C, totalCount: Int) {
		//Send initial server information
		var packer = AirPacker()
		packer.pack(int: NHT.information.rawValue)
		
		packer.pack(int: CommConst.version)
		packer.pack(int: CommConst.subVersion)
		
		if dataProxy.requiresAuthentication {
			//Generate a transmission check
			let transmissionCheck: Data
			do {
				transmissionCheck = try generateSecureData(count: CommConst.transmissionCheckLength)
			} catch {
				LogManager.log("Failed to generate transmission check: \(error)", level: .error)
				dataProxy.disconnect(client: client)
				return
			}
			
			packer.pack(bool: true) //Transmission check required
			packer.pack(payload: transmissionCheck)
			
			client.transmissionCheck = transmissionCheck
		} else {
			packer.pack(bool: false) //Transmission check not required
		}
		
		dataProxy.send(message: packer.data, to: client, encrypt: false, onSent: nil)
		
		//Start the expiry timer
		client.startTimer(ofType: .handshakeExpiry, interval: CommConst.handshakeTimeout) { [weak self] client in
			LogManager.log("Handshake response for client \(client.readableID) timed out, disconnecting", level: .debug)
			self?.dataProxy?.disconnect(client: client)
		}
	}
	
	func dataProxy(_ dataProxy: DataProxy, didDisconnectClient client: C, totalCount: Int) {
		//Clean up pending timers
		client.cancelAllTimers()
	}
	
	func dataProxy(_ dataProxy: DataProxy, didReceive data: Data, from client: C, wasEncrypted: Bool) {
		var packer = AirPacker(from: data)
		
		//Read the common message data
		let messageTypeRaw: Int32
		do {
			messageTypeRaw = try packer.unpackInt()
		} catch {
			LogManager.log("Failed to unpack received message header: \(error)", level: .error)
			return
		}
		
		//Map the message type
		guard let messageType = NHT(rawValue: messageTypeRaw) else {
			LogManager.log("Received unknown NHT \(messageTypeRaw)", level: .notice)
			return
		}
		
		do {
			if wasEncrypted {
				try processMessageSensitive(dataProxy: dataProxy, packer: &packer, from: client, type: messageType)
			} else {
				try processMessageStandard(dataProxy: dataProxy, packer: &packer, from: client, type: messageType)
			}
		} catch {
			LogManager.log("Failed to handle message of type \(messageType.rawValue): \(error)", level: .notice)
		}
	}
}
