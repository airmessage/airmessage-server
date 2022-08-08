//
//  DatabaseManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-11.
//

import Foundation
import SQLite

class DatabaseManager {
	//Instance
	public static let shared = DatabaseManager()
	
	//Constants
	private static let databaseLocation = NSHomeDirectory() + "/Library/Messages/chat.db"
	
	//Dispatch queues
	private let queueScanner = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".database.scanner", qos: .utility)
	
	//Timers
	private var timerScanner: DispatchSourceTimer?
	
	//Database state
	private let initTime: Int64 //Time initialized in DB time
	private var dbConnection: Connection?
	
	//Query state
	private let _lastScannedMessageID = AtomicValue<Int64?>(initialValue: nil)
	public var lastScannedMessageID: Int64? {
		_lastScannedMessageID.value
	}
	private struct MessageTrackingState: Equatable {
		let id: Int64
		let state: MessageInfo.State
	}
	private var messageStateDict: [Int64: MessageTrackingState] = [:] //chat ID: message state
	
	private init() {
		initTime = getDBTime()
	}
	
	deinit {
		//Make sure timers are canceled on deinit
		stop()
	}
	
	func start() throws {
		//Connect to the database
		dbConnection = try Connection(DatabaseManager.databaseLocation, readonly: true)
		
		//Start the scanner timer
		let timer = DispatchSource.makeTimerSource(queue: queueScanner)
		timer.schedule(deadline: .now(), repeating: .seconds(2))
		timer.setEventHandler { [weak self] in
			self?.runScan()
		}
		timer.resume()
		timerScanner = timer
	}
	
	func stop() {
		//Disconnect from the database
		dbConnection = nil
		
		//Stop the scanner timer
		timerScanner?.cancel()
		timerScanner = nil
	}
	
	//MARK: Scanner
	
	private func runScan() {
		guard let dbConnection = dbConnection else {
			LogManager.log("Trying to run scan, but database is unavailable", level: .error)
			return
		}

		do {
			//Build the WHERE clause and fetch messages
			let whereClause: String
			do {
				if let id = _lastScannedMessageID.value {
					//If we've scanned previously, only search for messages with a higher ID than last time
					whereClause = "message.ROWID > \(id)"
				} else {
					//If we have no previous scan data, search for messages added since we first started scanning
					whereClause = "message.date > \(initTime)"
				}
			}
			let stmt = try fetchMessages(using: dbConnection, where: whereClause)
			let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
			let rows = try stmt.map { row -> (id: Int64, messageRow: DatabaseMessageRow?) in
				//Get the row ID
				let rowID = row[indices["message.ROWID"]!] as! Int64
				
				//Process the message row
				let messageRow = try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
				
				return (rowID, messageRow)
			}
			
			//Collect new additions
			let (conversationItems, looseModifiers) = DatabaseConverter.groupMessageRows(rows.map { $0.messageRow }).destructured
			
			//Set to the latest message ID, only we hit a new max
			var updatedMessageID: Int64?
			
			//Update the latest message ID
			if rows.isEmpty {
				updatedMessageID = nil
			} else {
				_lastScannedMessageID.with { value in
					let maxID = rows.reduce(Int64.min) { lastID, row in
						max(lastID, row.id)
					}
					
					if value == nil || maxID > value! {
						value = maxID
						updatedMessageID = maxID
					} else {
						updatedMessageID = nil
					}
				}
			}
			
			//Check for updated message states
			let messageStateUpdates = try updateMessageStates()
			
			//Send message updates
			if !conversationItems.isEmpty {
				ConnectionManager.shared.send(messageUpdate: conversationItems)
			}
			
			//Send modifier updates
			let combinedModifiers = looseModifiers + messageStateUpdates
			if !combinedModifiers.isEmpty {
				ConnectionManager.shared.send(modifierUpdate: combinedModifiers)
			}
			
			//Send push notifications
			ConnectionManager.shared.sendPushNotification(
				messages: conversationItems.compactMap { conversationItem in
					//Only notify incoming messages
					if let message = conversationItem as? MessageInfo, message.sender != nil {
						return message
					} else {
						return nil
					}
				},
				modifiers: looseModifiers.filter { modifier in
					//Only notify incoming tapbacks
					if let tapback = modifier as? TapbackModifierInfo, tapback.sender != nil {
						return true
					} else {
						return false
					}
				}
			)
			
			//Notify clients of the latest message ID
			if let id = updatedMessageID {
				ConnectionManager.shared.send(idUpdate: id, to: nil)
			}
		} catch {
			LogManager.log("Error fetching scan data: \(error)", level: .error)
		}
	}
	
	/**
	 Runs a check for any updated message states
	 - Parameter db: The connection to query
	 - Returns: An array of activity status updates
	 - Throws: SQL execution errors
	 */
	private func updateMessageStates() throws -> [ActivityStatusModifierInfo] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		//Create the result array
		var resultArray: [ActivityStatusModifierInfo] = []
		
		//Get the most recent outgoing message for each conversation
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryOutgoingMessages", withExtension: "sql", subdirectory: "SQL")!)
		let query = String(format: template, "") //Don't add any special WHERE clauses
		let stmt = try dbConnection.prepare(query)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		//Keep track of chats that don't show up in our query, so we can remove them from our tracking dict
		var untrackedChats: Set<Int64> = Set(messageStateDict.keys)
		for row in stmt {
			//Read the row data
			let chatID = row[indices["chat.ROWID"]!] as! Int64
			let messageID = row[indices["message.ROWID"]!] as! Int64
			let modifier = DatabaseConverter.processActivityStatusRow(row, withIndices: indices)
			
			//Remove this chat from the untracked chats
			untrackedChats.remove(chatID)
			
			//Create an entry for this update
			let newUpdate = MessageTrackingState(id: messageID, state: modifier.state)
			
			//Compare against the existing update
			if let existingUpdate = messageStateDict[chatID] {
				if existingUpdate != newUpdate {
					LogManager.log("Discovered activity status update for message \(modifier.messageGUID): \(existingUpdate) -> \(newUpdate)", level: .info)
					
					//Create an update
					if newUpdate.state != .idle && newUpdate.state != .sent {
						resultArray.append(modifier)
					}
					
					//Update the dictionary entry
					messageStateDict[chatID] = newUpdate
				}
			} else {
				//Add this update to the dictionary
				messageStateDict[chatID] = newUpdate
			}
		}
		
		//Remove all untracked chats from the tracking dict
		for chatID in untrackedChats {
			messageStateDict[chatID] = nil
		}
		
		//Return the results
		return resultArray
	}
	
	//MARK: Fetch
	
	/**
	 Fetches a standard set of fields for messages
	 - Parameters:
	   - db: The connection to query
	   - queryWhere: A statement to be appended to the WHERE clause
	 - Returns: The executed statement
	 - Throws: SQL execution errors
	 */
	private func fetchMessages(using db: Connection, where queryWhere: String? = nil, sort querySort: String? = nil, limit queryLimit: Int? = nil, bindings queryBindings: [Binding?] = []) throws -> Statement {
		var rows: [String] = [
			"message.ROWID",
			"message.guid",
			"message.date",
			"message.item_type",
			"message.group_action_type",
			"message.attributedBody",
			"message.subject",
			"message.error",
			"message.date_read",
			"message.is_from_me",
			"message.group_title",
			"message.is_sent",
			"message.is_read",
			"message.is_delivered",
			
			"sender_handle.id",
			"other_handle.id",
			
			"chat.guid"
		]
		
		if #available(macOS 10.12, *) {
			rows += [
				"message.expressive_send_style_id",
				"message.associated_message_guid",
				"message.associated_message_type",
				"message.associated_message_range_location"
			]
		}
		
		var extraClauses: [String] = []
		if let queryWhere = queryWhere {
			extraClauses.append("WHERE \(queryWhere)")
		}
		if let querySort = querySort {
			extraClauses.append("ORDER BY \(querySort)")
		}
		if let queryLimit = queryLimit {
			extraClauses.append("LIMIT \(queryLimit)")
		}
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryMessageChatHandle", withExtension: "sql", subdirectory: "SQL")!)
		let query = String(format: template,
						   rows.map { "\($0) AS \"\($0)\"" }.joined(separator: ", "),
						   extraClauses.joined(separator: " ")
		)
		return try db.prepare(query, queryBindings)
	}
	
	//MARK: Requests
	
	/**
	 Fetches grouped messages from a specified time range
	 */
	public func fetchGrouping(fromTime timeLowerUNIX: Int64, to timeUpperUNIX: Int64) throws -> DBFetchGrouping {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		//Convert the times to database times
		let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
		let timeUpper = convertDBTime(fromUNIX: timeUpperUNIX)
		
		let stmt = try fetchMessages(using: dbConnection, where: "message.date > ? AND message.date < ?", bindings: [timeLower, timeUpper])
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		let rows = try stmt.map { row in
			try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
		}
		return DatabaseConverter.groupMessageRows(rows)
	}
	
	/**
	 Fetches messages since a specified ID (exclusive)
	 */
	public func fetchGrouping(fromID idLower: Int64) throws -> DBFetchGrouping {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		let stmt = try fetchMessages(using: dbConnection, where: "message.ROWID > ?", bindings: [idLower])
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		let rows = try stmt.map { row in
			try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
		}
		return DatabaseConverter.groupMessageRows(rows)
	}
	
	/**
	 Fetches an array of updated `ActivityStatusModifierInfo` after a certain time
	 */
	public func fetchActivityStatus(fromTime timeLowerUNIX: Int64) throws -> [ActivityStatusModifierInfo] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		//Convert the time to database time
		let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryOutgoingMessages", withExtension: "sql", subdirectory: "SQL")!)
		let query = String(format: template, "AND (message.date_delivered > \(timeLower) OR message.date_read > \(timeLower))")
		let stmt = try dbConnection.prepare(query)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return stmt.map { row in
			DatabaseConverter.processActivityStatusRow(row, withIndices: indices)
		}
	}
	
	struct AttachmentFile {
		let url: URL
		let type: String?
		let name: String
	}
	
	/**
	 Fetches the path to the file of the attachment of GUID guid
	 */
	public func fetchFile(fromAttachmentGUID guid: String) throws -> AttachmentFile? {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		//Run the query
		let stmt = try dbConnection.prepare("SELECT filename, mime_type, transfer_name FROM attachment WHERE guid = ? LIMIT 1", guid)
		
		//Return nil if there are no results
		guard let row = stmt.next() else {
			return nil
		}
		
		//Read the query result
		let path = row[0] as! String?
		let type = row[1] as! String?
		let name = row[2] as! String
		
		//Return nil if there is no file path
		guard let path = path else {
			return nil
		}
		
		//Return the file
		return AttachmentFile(url: DatabaseConverter.createURL(dbPath: path), type: type, name: name)
	}
	
	/**
	 Fetches an array of conversations from their GUID, returning an array of mixed available and unavailable conversations
	 */
	public func fetchBaseConversations(in guidArray: [String]) throws -> [BaseConversationInfo] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		let query = try! String(contentsOf: Bundle.main.url(forResource: "QuerySpecificChatDetails", withExtension: "sql", subdirectory: "SQL")!)
		
		//Update the query to take as many parameters as we have
		let queryParameterTemplate = Array(repeating: "?", count: guidArray.count).joined(separator: ", ")
		let queryMultipleParams = query.replacingOccurrences(of: "?", with: queryParameterTemplate)
		
		let stmt = try dbConnection.prepare(queryMultipleParams, guidArray)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		//Fetch available conversations and map them to ConverationInfos
		let availableArray = stmt.map { DatabaseConverter.processConversationRow($0, withIndices: indices) }
		
		//Fill in conversations that weren't found in the database as UnavailableConversationInfos
		let unavailableArray = guidArray.filter { guid in
			!availableArray.contains { availableConversation in
				availableConversation.guid == guid
			}
		}.map { guid in UnavailableConversationInfo(guid: guid) }
		
		return availableArray + unavailableArray
	}
	
	/**
	 Fetches an array of conversations, optionally that have had activity since a certain time
	 */
	public func fetchConversationArray(since timeLowerUNIX: Int64? = nil) throws -> [ConversationInfo] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		let stmt: Statement
		if let timeLowerUNIX = timeLowerUNIX {
			let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
			
			let query = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatDetailsSince", withExtension: "sql", subdirectory: "SQL")!)
			stmt = try dbConnection.prepare(query, timeLower)
		} else {
			let query = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatDetails", withExtension: "sql", subdirectory: "SQL")!)
			stmt = try dbConnection.prepare(query)
		}
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return stmt.map { DatabaseConverter.processConversationRow($0, withIndices: indices) }
	}
	
	/**
	 Counts the number of message rows, optionally since a certain time
	 */
	public func countMessages(since timeLowerUNIX: Int64? = nil) throws -> Int64 {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		if let timeLowerUNIX = timeLowerUNIX {
			let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
			
			return try dbConnection.scalar("SELECT count(*) FROM message WHERE message.date > ?", timeLower) as! Int64
		} else {
			return try dbConnection.scalar("SELECT count(*) FROM message") as! Int64
		}
	}
	
	enum FailableDatabaseMessageRow {
		case deallocError
		case sqlError(Error)
		case row(DatabaseMessageRow?)

		var isError: Bool {
			switch self {
				case .row:
					return false
				default:
					return true
			}
		}
		
		var row: DatabaseMessageRow? {
			switch self {
				case .row(let row):
					return row
				default:
					return nil
			}
		}
	}
	
	/**
	 Returns a lazy iterator over a sequence of `FailableDatabaseMessageRow`
	 */
	public func fetchMessagesLazy(since timeLowerUNIX: Int64? = nil) throws -> LazyMessageIterator {
		//Fetch the messages
		let stmt: Statement
		do {
			guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
			
			if let timeLowerUNIX = timeLowerUNIX {
				let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
				
				stmt = try fetchMessages(using: dbConnection, where: "message.date > ?", bindings: [timeLower])
			} else {
				stmt = try fetchMessages(using: dbConnection)
			}
		}
		
		//Return a lazy iterator
		return LazyMessageIterator(databaseManager: self, stmt: stmt)
	}
	
	class LazyMessageIterator: IteratorProtocol {
		private let databaseManager: DatabaseManager
		private let stmt: Statement
		private let indices: [String: Int]
		
		init(databaseManager: DatabaseManager, stmt: Statement) {
			self.databaseManager = databaseManager
			self.stmt = stmt
			indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		}
		
		func next() -> FailableDatabaseMessageRow? {
			//Get the next message row
			let row: [Binding?]?
			do {
				row = try stmt.failableNext()
			} catch {
				//Finish iteration if an error occurred
				LogManager.log("Encountered an error while lazily iterating over messages: \(error)", level: .notice)
				return nil
			}
			
			//No more rows, finish the iterator
			guard let row = row else { return nil }
			
			//Make sure we're still connected to the database
			guard let db = databaseManager.dbConnection else {
				return .deallocError
			}
			
			//Fetch the row
			let message: DatabaseMessageRow?
			do {
				message = try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: db)
			} catch {
				return .sqlError(error)
			}
			
			//Return the row
			return .row(message)
		}
	}
	
	/**
	 Fetches all `LiteConversationInfo` from the database
	 */
	public func fetchLiteConversations() throws -> [LiteConversationInfo] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		let extraRows: [String]
		if #available(macOS 10.12, *) {
			extraRows = ["message.expressive_send_style_id"]
		} else {
			extraRows = []
		}
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatSummary", withExtension: "sql", subdirectory: "SQL")!)
		let query = String(format: template, extraRows.isEmpty ? "" : ", " + extraRows.map { "\($0) AS \"\($0)\"" }.joined(separator: ", "))
		let stmt = try dbConnection.prepare(query)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return stmt.map { row in DatabaseConverter.processLiteConversationRow(row, withIndices: indices) }
	}
	
	/**
	 Fetches a small collection of messages from newest to oldest.
	 For pagination, `before` should be passed.
	 */
	public func fetchLiteThread(chatGUID: String, before: Int64?) throws -> [ConversationItem] {
		guard let dbConnection = dbConnection else { throw DatabaseDisconnectedError() }
		
		//Filter by chat and optionally message ID
		var fetchWhere: String = "chat.GUID = ?"
		var fetchBindings: [Binding?] = [chatGUID]
		if let before = before {
			fetchWhere += " AND message.ROWID < ?"
			fetchBindings.append(before)
		}
		
		//Fetch messages from newest to oldest
		let stmt = try fetchMessages(
			using: dbConnection,
			where: fetchWhere,
			sort: "message.ROWID DESC",
			bindings: fetchBindings
		)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		/*
		 Messages are iterated in reverse order.
		 In order to properly apply modifiers, we'll keep track of any modifiers
		 that we hit in a dictionary keyed by their message GUID.
		 We can pull in these modifiers when we reach the target message.
		 
		 This does mean that if a message and its modifiers are queried for in
		 separate requests, the modifiers will be dropped.
		 */
		var conversationItemArray: [ConversationItem] = []
		var isolatedModifierDict: [String: [ModifierInfo]] = [:]
		
		//Collect up to 24 message items
		while conversationItemArray.count < 24 {
			let row = try stmt.failableNext()
			
			//End of iterator, exit loop
			guard let row = row else {
				break
			}
			
			//Process the message row
			let messageRow = try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
			guard let messageRow = messageRow else { continue }
			
			switch messageRow {
				case .message(let conversationItem):
					if var message = conversationItem as? MessageInfo {
						//Apply any modifiers
						if let modifierArray = isolatedModifierDict[message.guid] {
							for modifier in modifierArray {
								switch modifier {
									case let tapback as TapbackModifierInfo:
										message.tapbacks.append(tapback)
									case let sticker as StickerModifierInfo:
										message.stickers.append(sticker)
									default:
										break
								}
							}
						}
						
						//Save the message
						conversationItemArray.append(message)
					} else {
						//Save the conversation item
						conversationItemArray.append(conversationItem)
					}
				case .modifier(let modifier):
					//Record the modifier for later reference
					isolatedModifierDict[modifier.messageGUID] = (isolatedModifierDict[modifier.messageGUID] ?? []) + [modifier]
			}
		}
		
		return conversationItemArray
	}
}

struct DatabaseDisconnectedError: Error {
	let localizedDescription = "Database is not connected"
}
