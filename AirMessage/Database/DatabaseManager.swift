//
//  DatabaseManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-11.
//

import Foundation
import SQLite

class DatabaseManager {
	//Constants
	private static let databaseLocation = NSHomeDirectory() + "/Library/Messages/chat.db"
	
	//Dispatch queues
	private let queueScanner = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".database.scanner", qos: .utility)
	private let queueRequests = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".database.request", qos: .userInitiated)
	
	//Timers
	private var timerScanner: DispatchSourceTimer?
	
	//Database state
	private let dbConnection: Connection
	
	//Query state
	private let initTime: Int64 //Time initialized in DB time
	private var lastScannedMessageID: Int64? = nil
	private struct MessageTrackingState: Equatable {
		let id: Int64
		let state: MessageInfo.State
	}
	private var messageStateDict: [Int64: MessageTrackingState] = [:] //chat ID : message state
	
	init() throws {
		dbConnection = try Connection(DatabaseManager.databaseLocation)
		initTime = getDBTime()
	}
	
	deinit {
		//Make sure timers are canceled on deinit
		cancel()
	}
	
	func resume() {
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
		timerScanner?.cancel()
		timerScanner = nil
	}
	
	func runScan() {
		do {
			//Build the WHERE clause and fetch messages
			let whereClause: String
			if let id = lastScannedMessageID {
				//If we've scanned previously, only search for messages with a higher ID than last time
				whereClause = "message.ROWID > \(id)"
			} else {
				//If we have no previous scan data, search for messages added since we first started scanning
				whereClause = "message.date > \(initTime)"
			}
			let stmt = try fetchMessages(using: dbConnection, where: whereClause)
			let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
			
			//Collect new additions
			var conversationItemArray: [ConversationItem] = []
			//Modifiers that couldn't be attached to a conversation,
			//and should be sent separately to clients
			var looseModifiers: [ModifierInfo] = []
			for row in stmt {
				switch try DatabaseConverter.processMessageRow(row, withIndices: indices, ofDB: dbConnection) {
					case .message(let message):
						conversationItemArray.append(message)
						break
					case .modifier(let modifier):
						//Find the associated message
						if let conversationItemIndex = conversationItemArray.lastIndex(where: { $0.guid == modifier.messageGUID }) {
							let conversationItem = conversationItemArray[conversationItemIndex]
							
							//Make sure the conversation item is a message
							guard var message = conversationItem as? MessageInfo else { continue }
							
							//Add the modifier to the message
							if let tapback = modifier as? TapbackModifierInfo {
								message.tapbacks.append(tapback)
							} else if let sticker = modifier as? StickerModifierInfo {
								message.stickers.append(sticker)
							}
							conversationItemArray[conversationItemIndex] = message
						} else {
							looseModifiers.append(modifier)
						}
						
						break
					case .none:
						break
				}
			}
			
			//Update the latest message ID
			if !conversationItemArray.isEmpty {
				lastScannedMessageID = conversationItemArray.reduce(0) { lastID, item in
					max(lastID, item.serverID)
				}
			}
			
			//Check for updated message states
			let messageStateUpdates = try updateMessageStates(using: dbConnection)
		} catch {
			LogManager.shared.log("Error fetching scan data: %{public}", type: .notice, error.localizedDescription)
		}
	}
	
	/**
	 Fetches a standard set of fields for messages
	 - Parameters:
	   - db: The connection to query
	   - queryWhere: A statement to be appended to the WHERE clause
	 - Returns: The executed statement
	 - Throws: SQL execution errors
	 */
	func fetchMessages(using db: Connection, where queryWhere: String? = nil) throws -> Statement {
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
		
		let template = try! String(contentsOf: Bundle.main.url(forResource: "QueryMessageChatHandle", withExtension: "sql")!)
		let query = String(format: template,
				rows.joined(separator: ", "),
				queryWhere != nil ? "WHERE \(queryWhere!)" : ""
		)
		return try db.prepare(query)
	}
	
	/**
	 Runs a check for any updated message states
	 - Parameter db: The connection to query
	 - Returns: An array of activity status updates
	 - Throws: SQL execution errors
	 */
	func updateMessageStates(using db: Connection) throws -> [ActivityStatusModifierInfo] {
		//Create the result array
		var resultArray: [ActivityStatusModifierInfo] = []
		
		//Get the most recent outgoing message for each conversation
		let query = try! String(contentsOf: Bundle.main.url(forResource: "QueryOutgoingMessages", withExtension: "sql")!)
		let stmt = try db.prepare(query)
		let indices = DatabaseConverter.makeColumnIndexDict(stmt.columnNames)
		
		//Keep track of chats that don't show up in our query, so we can remove them from our tracking dict
		var untrackedChats: Set<Int64> = Set(messageStateDict.keys)
		for row in stmt {
			//Read the row data
			let chatID = row[indices["chat.ROWID"]!] as! Int64
			let messageID = row[indices["message.ROWID"]!] as! Int64
			let messageGUID = row[indices["message.guid"]!] as! String
			let state = DatabaseConverter.mapMessageStateCode(
					isSent: row[indices["message.is_sent"]!] as! Bool,
					isDelivered: row[indices["message.is_delivered"]!] as! Bool,
					isRead: row[indices["message.is_read"]!] as! Bool
			)
			let dateRead = row[indices["message.date_read"]!] as! Int64
			
			//Remove this chat from the untracked chats
			untrackedChats.remove(chatID)
			
			//Create an entry for this update
			let newUpdate = MessageTrackingState(id: messageID, state: state)
			
			//Compare against the existing update
			if let existingUpdate = messageStateDict[chatID] {
				if existingUpdate != newUpdate {
					//Create an update
					resultArray.append(ActivityStatusModifierInfo(messageGUID: messageGUID, state: state, dateRead: dateRead))
					
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
}