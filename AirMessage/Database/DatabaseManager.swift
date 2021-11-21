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
	private var dbConnection: Connection!
	
	//Query state
	private let lastScannedMessageIDLock = NSLock()
	private var _lastScannedMessageID: Int64? = nil
	public var lastScannedMessageID: Int64? {
		lastScannedMessageIDLock.lock()
		defer { lastScannedMessageIDLock.unlock() }
		return _lastScannedMessageID
	}
	private struct MessageTrackingState: Equatable {
		let id: Int64
		let state: MessageInfo.State
	}
	private var messageStateDict: [Int64: MessageTrackingState] = [:] //chat ID : message state
	
	private init() {
		initTime = getDBTime()
	}
	
	deinit {
		//Make sure timers are canceled on deinit
		cancel()
	}
	
	func resume() throws {
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
	
	func cancel() {
		//Disconnect from the database
		dbConnection = nil
		
		//Stop the scanner timer
		timerScanner?.cancel()
		timerScanner = nil
	}
	
	//MARK: Scanner
	
	private func runScan() {
		do {
			//Build the WHERE clause and fetch messages
			let whereClause: String
			do {
				if let id = lastScannedMessageID {
					//If we've scanned previously, only search for messages with a higher ID than last time
					whereClause = "message.ROWID > \(id)"
				} else {
					//If we have no previous scan data, search for messages added since we first started scanning
					whereClause = "message.date > \(initTime)"
				}
			}
			let stmt = try fetchMessages(using: dbConnection, where: whereClause)
			let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
			let rows = try stmt.map { row in
				try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
			}
			
			//Collect new additions
			let (conversationItems, looseModifiers) = DatabaseConverter.groupMessageRows(rows).destructured
			
			//Set to the latest message ID, only we hit a new max
			let updatedMessageID: Int64?
			
			//Update the latest message ID
			if conversationItems.isEmpty {
				updatedMessageID = nil
			} else {
				lastScannedMessageIDLock.lock()
				defer { lastScannedMessageIDLock.unlock() }
				
				let maxID = conversationItems.reduce(Int64.min) { lastID, item in
					max(lastID, item.serverID)
				}
				
				if _lastScannedMessageID == nil || maxID > _lastScannedMessageID! {
					_lastScannedMessageID = maxID
					updatedMessageID = maxID
				} else {
					updatedMessageID = nil
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
			LogManager.shared.log("Error fetching scan data: %{public}", type: .notice, error.localizedDescription)
		}
	}
	
	/**
	 Runs a check for any updated message states
	 - Parameter db: The connection to query
	 - Returns: An array of activity status updates
	 - Throws: SQL execution errors
	 */
	private func updateMessageStates() throws -> [ActivityStatusModifierInfo] {
		//Create the result array
		var resultArray: [ActivityStatusModifierInfo] = []
		
		//Get the most recent outgoing message for each conversation
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryOutgoingMessages", withExtension: "sql")!)
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
					//Create an update
					resultArray.append(modifier)
					
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
	private func fetchMessages(using db: Connection, where queryWhere: String? = nil, sort querySort: String? = nil, limit queryLimit: Int? = nil) throws -> Statement {
		var rows: [String] = [
			"message.ROWID",
			"message.guid",
			"message.date",
			"message.item_type",
			"message.group_action_type",
			"message.text",
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
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryMessageChatHandle", withExtension: "sql")!)
		let query = String(format: template,
				rows.joined(separator: ", "),
				extraClauses.joined(separator: " ")
		)
		return try db.prepare(query)
	}
	
	//MARK: Requests
	
	/**
	 Fetches grouped messages from a specified time range
	 */
	public func fetchGrouping(fromTime timeLowerUNIX: Int64, to timeUpperUNIX: Int64) throws -> DBFetchGrouping {
		//Convert the times to database times
		let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
		let timeUpper = convertDBTime(fromUNIX: timeUpperUNIX)
		
		let stmt = try fetchMessages(using: dbConnection, where: "message.date > \(timeLower) AND message.date < \(timeUpper)")
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
		let stmt = try fetchMessages(using: dbConnection, where: "message.ROWID > \(idLower)")
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
		//Convert the time to database time
		let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryOutgoingMessages", withExtension: "sql")!)
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
		//Run the query
		let stmt = try dbConnection.prepare("SELECT filename, mime_type, transfer_name FROM attachment WHERE guid = ? LIMIT 1", guid)
		
		//Return nil if there are no results
		guard let row = stmt.next() else {
			return nil
		}
		
		//Return the file
		let filename = row[0] as! String
		let type = row[1] as? String
		let name = row[2] as! String
		return AttachmentFile(url: DatabaseConverter.createURL(dbPath: filename), type: type, name: name)
	}
	
	/**
	 Fetches an array of conversations from their GUID, returning an array of mixed available and unavailable conversations
	 */
	public func fetchConversationArray(in guidArray: [String]) throws -> [BaseConversationInfo] {
		let query = try! String(contentsOf: Bundle.main.url(forResource: "QuerySpecificChatDetails", withExtension: "sql")!)
		let stmt = try dbConnection.prepare(query, guidArray)
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
		let stmt: Statement
		if let timeLowerUNIX = timeLowerUNIX {
			let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
			
			let query = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatDetailsSince", withExtension: "sql")!)
			stmt = try dbConnection.prepare(query, timeLower)
		} else {
			let query = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatDetails", withExtension: "sql")!)
			stmt = try dbConnection.prepare(query)
		}
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return stmt.map { DatabaseConverter.processConversationRow($0, withIndices: indices) }
	}
	
	/**
	 Counts the number of message rows, optionally since a certain time
	 */
	public func countMessages(since timeLowerUNIX: Int64? = nil) throws -> Int {
		if let timeLowerUNIX = timeLowerUNIX {
			let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
			
			return try dbConnection.scalar("SELECT count(*) FROM message WHERE message.date > ?", timeLower) as! Int
		} else {
			return try dbConnection.scalar("SELECT count(*) FROM message") as! Int
		}
	}
	
	enum FailableDatabaseMessageRow {
		case deallocError
		case sqlError(Error)
		case dataError
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
	public func fetchMessagesLazy(since timeLowerUNIX: Int64? = nil) throws -> LazyMapSequence<LazyFilterSequence<LazyMapSequence<LazySequence<Statement>.Elements, DatabaseManager.FailableDatabaseMessageRow?>>, DatabaseManager.FailableDatabaseMessageRow> {
		//Fetch the messages
		let stmt: Statement
		if let timeLowerUNIX = timeLowerUNIX {
			let timeLower = convertDBTime(fromUNIX: timeLowerUNIX)
			
			stmt = try fetchMessages(using: dbConnection, where: "message.date > \(timeLower)")
		} else {
			stmt = try fetchMessages(using: dbConnection)
		}
		
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		return stmt.lazy.compactMap { [dbConnection] row -> FailableDatabaseMessageRow in
			//Make sure we still have a reference to the database
			guard let db = dbConnection else {
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
		let extraRows: [String]
		if #available(macOS 10.12, *) {
			extraRows = ["message.expressive_send_style_id"]
		} else {
			extraRows = []
		}
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryAllChatSummary", withExtension: "sql")!)
		let query = String(format: template, extraRows.isEmpty ? "" : ", " + extraRows.joined(separator: ", "))
		let stmt = try dbConnection.prepare(query)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return stmt.map { row in DatabaseConverter.processLiteConversationRow(row, withIndices: indices) }
	}
	
	/**
	 Fetches a small collection of messages from newest to oldest.
	 For pagination, `before` should be passed.
	 */
	public func fetchLiteThread(chatGUID: String, before: Int64?) throws -> [ConversationItem] {
		let stmt = try fetchMessages(
			using: dbConnection,
			where: before.map { "message.ROWID < \($0)" },
			sort: "message.ROWID DESC"
		)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		return try stmt.map { row in
			try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection)
		}.compactMap { row -> ConversationItem? in
			switch row {
				case .message(let conversationItem):
					return conversationItem
				default:
					//Discard modifiers
					return nil
			}
		}
	}
}
