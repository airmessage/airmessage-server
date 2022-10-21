//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation
import SQLite
import Sentry

class DatabaseConverter {
	enum MessageItemType: Int {
		case message = 0
		case groupAction = 1
		case chatRename = 2
		case chatLeave = 3
	}
	
	private init() {}
	
	/**
	 Groups an array of message rows to messages and loose modifiers.
	 The array must have modifiers ordered after their associated message.
	 - Parameters:
	   - rows: The rows to group
	 - Returns: A tuple containing conversation items and loose modifiers
	 - Throws: SQL execution errors
	 */
	static func groupMessageRows(_ rows: [DatabaseMessageRow?]) -> DBFetchGrouping {
		var conversationItemArray: [ConversationItem] = []
		//Modifiers that couldn't be attached to a conversation,
		//and should be sent separately to clients
		var looseModifiers: [ModifierInfo] = []
		
		for row in rows {
			switch row {
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
		
		return DBFetchGrouping(conversationItems: conversationItemArray, looseModifiers: looseModifiers)
	}
	
	/**
	 Processes a row database row of common columns into a `DatabaseMessageRow`
	 - Parameters:
	   - row: The row to process
	   - indices: The index dict to use to reference row columns
	   - db: The database to use for subsequent queries
	 - Returns: A `DatabaseMessageRow` that represents the information held in this row, or `nil` if the conversion failed
	 - Throws: SQL execution errors
	 */
	static func processMessageRow(_ row: Statement.Element, withIndices indices: [String: Int], ofDB db: Connection) throws -> DatabaseMessageRow? {
		//Common message parameters
		let rowID = row[indices["message.ROWID"]!] as! Int64
		let guid = row[indices["message.guid"]!] as! String
		let chatGUID = row[indices["chat.guid"]!] as! String
		let date = row[indices["message.date"]!] as! Int64
		
		let sender = (row[indices["message.is_from_me"]!] as! Int64 != 0) ? nil : (row[indices["sender_handle.id"]!] as! String?)
		let itemType = MessageItemType(rawValue: Int(row[indices["message.item_type"]!] as! Int64))
		
		if itemType == .message {
			if #available(macOS 10.12, *) {
				//Getting the association info
				let associatedMessage = row[indices["message.associated_message_guid"]!] as! String?
				let associationType = row[indices["message.associated_message_type"]!] as! Int64
				let associationIndex = row[indices["message.associated_message_range_location"]!] as! Int64
				
				//Checking if there is an association
				if associationType != 0 {
					guard let associatedMessage = associatedMessage else {
						LogManager.log("Expected an associated message GUID for message \(guid), none found", level: .error)
						return nil
					}
					
					//Example association string: p:0/69C164B2-2A14-4462-87FA-3D79094CFD83
					//Splitting the association between the protocol and GUID
					let associationData = associatedMessage.components(separatedBy: ":")
					
					let associatedMessageGUID: String
					//Associated with message extension (content from iMessage apps)
					if associationData[0] == "bp" {
						associatedMessageGUID = associationData[1]
					}
					//Standard association
					else if associationData[0] == "p" {
						//Get string after the '/'
						let part = associationData[1]
						associatedMessageGUID = String(part[part.index(after: part.firstIndex(of: "/")!)...])
					} else {
						//Unknown type
						LogManager.log("Encountered unexpected association data: \(associatedMessage)", level: .error)
						return nil
					}
					
					//Checking if the association is a sticker
					if associationType >= 1000 && associationType < 2000 {
						//Retrieving the sticker data
						guard let sticker = try fetchStickerData(ofMessage: rowID, ofDB: db) else {
							return nil
						}
						
						return .modifier(StickerModifierInfo(
								messageGUID: associatedMessageGUID,
								messageIndex: Int32(associationIndex),
								fileGUID: sticker.guid,
								sender: sender,
								date: convertDBTime(fromDB: date),
								data: sticker.data,
								type: sticker.type
						))
					}
					/*
					 Otherwise checking if the association is a tapback
					 2000 - 2999 = tapback added
					 3000 - 3999 = tapback removed
					 */
					else if associationType < 4000 {
						//Getting the tapback association info
						let tapbackAdded = associationType >= 2000 && associationType < 3000
						let tapbackType = associationType % 1000
						
						return .modifier(TapbackModifierInfo(
								messageGUID: associatedMessageGUID,
								messageIndex: Int32(associationIndex),
								sender: sender,
								isAddition: tapbackAdded,
								tapbackType: Int32(tapbackType)
						))
					}
				}
			}
			
			//Message-specific parameters
			let text = parseAttributedBody(withSQLiteBlob: row[indices["message.attributedBody"]!] as! SQLite.Blob?, withLogID: guid)
			let subject = row[indices["message.subject"]!] as! String?
			let sendEffect: String?
			if #available(macOS 10.12, *) {
				sendEffect = row[indices["message.expressive_send_style_id"]!] as! String?
			} else {
				sendEffect = nil
			}
			let state = mapMessageStateCode(
					isSent: row[indices["message.is_sent"]!] as! Int64 != 0,
					isDelivered: row[indices["message.is_delivered"]!] as! Int64 != 0,
					isRead: row[indices["message.is_read"]!] as! Int64 != 0
			)
			let error = mapMessageErrorCode(Int(row[indices["message.error"]!] as! Int64))
			let dateRead = row[indices["message.date_read"]!] as! Int64
			let attachments = try fetchAttachments(ofMessage: rowID, withChecksum: sender == nil, ofDB: db)
			
			let editHistory: [String]
			let isUnsent: Bool
			if #available(macOS 13.0, *) {
				let status = processEditedUnsentStatus(row, withIndices: indices, withLogID: guid)
				editHistory = status.editHistory
				isUnsent = status.isUnsent
			} else {
				editHistory = []
				isUnsent = false
			}
			
			return .message(MessageInfo(
					serverID: rowID,
					guid: guid,
					chatGUID: chatGUID,
					date: convertDBTime(fromDB: date),
					text: text,
					subject: subject,
					sender: sender,
					attachments: attachments,
					stickers: [],
					tapbacks: [],
					sendEffect: sendEffect,
					state: state,
					error: error,
					dateRead: convertDBTime(fromDB: dateRead),
					editHistory: editHistory,
					isUnsent: isUnsent
			))
		} else if itemType == .groupAction {
			let other = row[indices["other_handle.id"]!] as! String?
			let actionType = mapGroupActionType(Int(row[indices["message.group_action_type"]!] as! Int64))
			
			return .message(GroupActionInfo(
					serverID: rowID,
					guid: guid,
					chatGUID: chatGUID,
					date: convertDBTime(fromDB: date),
					agent: sender,
					other: other,
					subtype: actionType
			))
		} else if itemType == .chatRename {
			let chatName = row[indices["message.group_title"]!] as! String?
			
			return .message(ChatRenameActionInfo(
					serverID: rowID,
					guid: guid,
					chatGUID: chatGUID,
					date: convertDBTime(fromDB: date),
					agent: sender,
					updatedName: chatName
			))
		}
		
		return nil
	}
	
	/**
	 Processes a message database row into an `ActivityStatusModifierInfo`
	 - Parameters:
	   - row: The row to process
	   - indices: The index dict to use to reference row columns
	 - Returns: A `ActivityStatusModifierInfo` to represent the message row
	 */
	static func processActivityStatusRow(_ row: Statement.Element, withIndices indices: [String: Int]) -> ActivityStatusModifierInfo {
		//Read the row data
		let messageGUID = row[indices["message.guid"]!] as! String
		let state = DatabaseConverter.mapMessageStateCode(
				isSent: row[indices["message.is_sent"]!] as! Int64 != 0,
				isDelivered: row[indices["message.is_delivered"]!] as! Int64 != 0,
				isRead: row[indices["message.is_read"]!] as! Int64 != 0
		)
		let dateRead = row[indices["message.date_read"]!] as! Int64
		
		return ActivityStatusModifierInfo(messageGUID: messageGUID, state: state, dateRead: convertDBTime(fromDB: dateRead))
	}
	
	enum MessageSummaryParseError: Error {
		case typeError(Any)
	}
	
	/**
	 Processes a message row with edited content to an `EditedStatusModifierInfo`
	 - Parameters:
	   - row: The row to process
	   - indices: The index dict to use to reference row columns
	 - Returns: A `EditedStatusModifierInfo` that represents the information held in this row
	 */
	@available(macOS 13.0, *)
	static func processEditedStatusRow(_ row: Statement.Element, withIndices indices: [String: Int]) -> EditedStatusModifierInfo {
		//Read the row data
		let messageGUID = row[indices["message.guid"]!] as! String
		let status = processEditedUnsentStatus(row, withIndices: indices, withLogID: messageGUID)
		
		return EditedStatusModifierInfo(
				messageGUID: messageGUID,
				editHistory: status.editHistory,
				isUnsent: status.isUnsent
		)
	}
	
	/**
	 Processes a chat database row into a `ConversationInfo`
	 */
	static func processConversationRow(_ row: Statement.Element, withIndices indices: [String: Int]) -> ConversationInfo {
		let guid = row[indices["chat.guid"]!] as! String
		let name = row[indices["chat.display_name"]!] as! String?
		let service = row[indices["chat.service_name"]!] as! String
		let members: [String] = (row[indices["member_list"]!] as! String?)
			.map { $0.components(separatedBy: ",") } ?? []
		
		return ConversationInfo(guid: guid, service: service, name: name, members: members)
	}
	
	/**
	 Processes a chat database row into a `LiteConversationInfo`
	 */
	static func processLiteConversationRow(_ row: Statement.Element, withIndices indices: [String: Int]) -> LiteConversationInfo {
		let guid = row[indices["chat.guid"]!] as! String
		let service = row[indices["chat.service_name"]!] as! String
		let name = row[indices["chat.display_name"]!] as! String?
		let members = (row[indices["member_list"]!] as! String)
			.components(separatedBy: ",")
		
		let lastMessageDate = row[indices["message.date"]!] as! Int64
		let lastMessageText = parseAttributedBody(withSQLiteBlob: row[indices["message.attributedBody"]!] as! SQLite.Blob?)
		let lastMessageSendStyle: String?
		if #available(macOS 10.12, *) {
			lastMessageSendStyle = row[indices["message.expressive_send_style_id"]!] as! String?
		} else {
			lastMessageSendStyle = nil
		}
		let lastMessageSender: String? = (row[indices["message.is_from_me"]!] as! Int64 != 0) ? nil : (row[indices["handle.id"]!] as! String)
		let lastMessageAttachments = (row[indices["attachment_list"]!] as! String?)
			.map { $0.components(separatedBy: ",") } ?? []
		
		let isUnsent: Bool
		if #available(macOS 13.0, *) {
			isUnsent = processEditedUnsentStatus(row, withIndices: indices, withLogID: guid).isUnsent
		} else {
			isUnsent = false
		}
		
		return LiteConversationInfo(
			guid: guid,
			service: service,
			name: name,
			members: members,
			previewDate: convertDBTime(fromDB: lastMessageDate),
			previewSender: lastMessageSender,
			previewText: lastMessageText,
			previewSendStyle: lastMessageSendStyle,
			previewAttachments: lastMessageAttachments,
			previewUnsent: isUnsent
		)
	}
	
	/**
	 Converts a string array to a dictionary that maps the string value to its index
	*/
	static func makeColumnIndexDict(_ columnNames: [String]) -> [String: Int] {
		columnNames.enumerated().reduce(into: [String: Int]()) { dict, element in
			dict[element.element] = element.offset
		}
	}
	
	//MARK: Fetch data
	
	/**
	 Fetches an array of attachments for a certain message
	 - Parameters:
	   - ofMessage: The ID of the message to fetch attachments for
	   - withChecksum: Whether to calculate the checksum of discovered attachments
	   - db: The database connection to use for queries
	 - Returns: An array of attachments associated with the message
	 - Throws: SQL-related errors
	 */
	static func fetchAttachments(ofMessage messageID: Int64, withChecksum: Bool, ofDB db: Connection) throws -> [AttachmentInfo] {
		var fields = [
			"attachment.ROWID",
			"attachment.guid",
			"attachment.filename",
			"attachment.transfer_name",
			"attachment.mime_type",
			"attachment.total_bytes"
		]
		if #available(macOS 10.12, *) {
			fields.append("attachment.hide_attachment")
		}
		
		let stmt = try db.prepare("""
		  SELECT \(fields.map { "\($0) AS \"\($0)\"" }.joined(separator: ", "))
		  FROM message_attachment_join
		  JOIN attachment ON message_attachment_join.attachment_id = attachment.ROWID
		  WHERE message_attachment_join.message_id = ?
		  """, messageID)
		
		let indices = makeColumnIndexDict(stmt.columnNames)
		let attachments = stmt.compactMap { row -> AttachmentInfo? in
			//Ignore hidden attachments
			if #available(macOS 10.12, *), row[indices["attachment.hide_attachment"]!] as! Int64 != 0 {
				return nil
			}
			
			//Ignore attachments with no transfer name
			guard row[indices["attachment.transfer_name"]!] != nil else {
				return nil
			}
			
			let guid = row[indices["attachment.guid"]!] as! String
			let name = row[indices["attachment.transfer_name"]!] as! String
			let type = row[indices["attachment.mime_type"]!] as! String?
			let size = row[indices["attachment.total_bytes"]!] as! Int64
			let url = (row[indices["attachment.filename"]!] as? String).map { createURL(dbPath: $0) }
			let checksum: Data?
			if withChecksum, let url = url {
				checksum = md5HashFile(url: url)
			} else {
				checksum = nil
			}
			let row = row[indices["attachment.ROWID"]!] as! Int64
			
			return AttachmentInfo(
					guid: guid,
					name: name,
					type: type,
					size: size,
					checksum: checksum,
					sort: row,
					localURL: url
			)
		}
		return attachments
	}
	
	struct StickerData {
		let type: String
		let guid: String
		let data: Data
	}
	
	/**
	 Fetches a sticker attachment for a given message
	 - Parameters:
	   - ofMessage: The ID of the message to fetch the sticker for
	   - db: The database connection to use for queries
	 - Returns: The sticker associated with the message
	 - Throws: SQL-related errors
	 */
	static func fetchStickerData(ofMessage messageID: Int64, ofDB db: Connection) throws -> StickerData? {
		let stmt: Statement
		stmt = try db.prepare("""
                                  SELECT attachment.guid AS "attachment.guid", attachment.filename AS "attachment.filename", attachment.mime_type AS "attachment.mime_type"
                                  FROM message_attachment_join
                                  JOIN attachment ON message_attachment_join.attachment_id = attachment.ROWID
                                  WHERE message_attachment_join.message_id = ?
                                  LIMIT 1
                                  """, messageID)
		let indices = makeColumnIndexDict(stmt.columnNames)
		guard let row = stmt.next(),
			  let filePath = row[indices["attachment.filename"]!] as? String,
			  var fileData = try? Data(contentsOf: createURL(dbPath: filePath)),
			  let fileDataCompressed = compressData(&fileData) else {
			return nil
		}
		
		let fileType = row[indices["attachment.mime_type"]!] as! String
		let fileGUID = row[indices["attachment.guid"]!] as! String
		
		return StickerData(
				type: fileType,
				guid: fileGUID,
				data: fileDataCompressed
		)
	}
	
	//MARK: Map Codes
	
	/**
	 Maps a series of boolean values from the database to a `MessageInfo.State`
	 */
	static func mapMessageStateCode(isSent: Bool, isDelivered: Bool, isRead: Bool) -> MessageInfo.State {
		if isRead {
			return .read
		} else if isDelivered {
			return .delivered
		} else if isSent {
			return .sent
		} else {
			return .idle
		}
	}
	
	/**
	 Maps a message error code from the database to a `MessageInfo.Error`
	 */
	static func mapMessageErrorCode(_ code: Int) -> MessageInfo.Error {
		switch code {
			case 0: return .ok
			case 3: return .network
			case 22: return .unregistered
			default: return .unknown
		}
	}
	
	/**
	 Maps a group action type to a `GroupActionInfo.Subtype`
	 */
	static func mapGroupActionType(_ code: Int) -> GroupActionInfo.Subtype {
		switch code {
			case 0: return .join
			case 1: return .leave
			default: return .unknown
		}
	}
	
	//MARK: Helpers
	
	enum AttributedBodyParseError: Error {
		case unarchiverError
		case typeError(Any?)
	}
	
	///Parses attributed body data and cleans it
	static func parseAttributedBody(withData data: Data) throws -> String? {
		//Create an unarchiver
		guard let unarchiver = NSUnarchiver(forReadingWith: data) else {
			throw AttributedBodyParseError.unarchiverError
		}
		
		//Retrieve the archive contents
		var decodedObject: Any?
		try ObjC.catchException {
			decodedObject = unarchiver.decodeObject()
		}
		
		guard let attributedString = decodedObject as? NSAttributedString else {
			throw AttributedBodyParseError.typeError(decodedObject)
		}
		
		return cleanMessageText(attributedString.string)
	}
	
	///Parses attributed body data from the database and cleans it
	static func parseAttributedBody(withSQLiteBlob body: SQLite.Blob?, withLogID logID: String? = nil) -> String? {
		//Skip if the body is nil
		guard let body = body else {
			return nil
		}
		
		//Parse the body
		do {
			return try parseAttributedBody(withData: Data.fromDatatypeValue(body))
		} catch {
			LogManager.log("Encountered an exception while decoding object for message \(logID ?? "unknown"): \(error)", level: .notice)
			return nil
		}
	}
	
	///Cleans a message string found in the database
	static func cleanMessageText(_ message: String?) -> String? {
		//Skip if the message is nil
		guard let message = message else { return nil }
		
		//Replace some characters that can magically appear in messages
		let cleanMessage = message.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\u{FFFD}", with: "")
		
		//Return nil if the message is empty
		if cleanMessage.isEmpty {
			return nil
		} else {
			return cleanMessage
		}
	}
	
	///Gets a message's edited and removed status
	@available(macOS 13.0, *)
	static func processEditedUnsentStatus(_ row: Statement.Element, withIndices indices: [String: Int], withLogID logID: String? = nil) -> EditedUnsentMessageStatus {
		guard let summaryInfo = row[indices["message.message_summary_info"]!] as? SQLite.Blob else {
			return EditedUnsentMessageStatus(editHistory: [], isUnsent: false)
		}
		
		//Parse the summary value
		var isUnsent = false
		var editHistory = [String]()
		do {
			//Parse the property list from memory
			let propertyList = try PropertyListSerialization.propertyList(from: Data.fromDatatypeValue(summaryInfo), format: nil)
			
			//Make sure the type is a dictionary
			guard let propertyListDict = propertyList as? [String: Any] else {
				throw MessageSummaryParseError.typeError(propertyList)
			}
			
			//Check for the removed array
			if let removedArray = propertyListDict["rp"] {
				do {
					guard let removedArray = removedArray as? [Int] else {
						throw MessageSummaryParseError.typeError(removedArray)
					}
					
					guard removedArray.first == 0 else {
						throw MessageSummaryParseError.typeError(removedArray)
					}
					
					isUnsent = true
				} catch {
					LogManager.log("Encountered an exception while decoding removed summary for message \(logID ?? "unknown"): \(error)", level: .notice)
					SentrySDK.capture(error: error)
				}
			}
			
			//Get the message history dictionary
			if let historyDict = propertyListDict["ec"] {
				do {
					//Convert the dictionary object to a concrete dictionary
					guard let messageHistoryDictionary = historyDict as? [String: Any] else {
						throw MessageSummaryParseError.typeError(historyDict)
					}
					
					//Get the first item of the message history dictionary
					guard let messageHistoryArray = messageHistoryDictionary["0"] as? [[String: Any]] else {
						throw MessageSummaryParseError.typeError(historyDict)
					}
					
					//Parse items (skip the last item, since it matches the current message)
					editHistory = try messageHistoryArray.compactMap { (entryDictionary) -> String? in
						guard let data = entryDictionary["t"] as? Data else {
							throw MessageSummaryParseError.typeError(historyDict)
						}
						
						return try parseAttributedBody(withData: data)
					}
				} catch {
					LogManager.log("Encountered an exception while decoding edit history summary for message \(logID ?? "unknown"): \(error)", level: .notice)
					SentrySDK.capture(error: error)
				}
			}
		} catch {
			LogManager.log("Encountered an exception while decoding summary for message \(logID ?? "unknown"): \(error)", level: .notice)
			SentrySDK.capture(error: error)
		}
		
		return EditedUnsentMessageStatus(
			editHistory: editHistory,
			isUnsent: isUnsent
		)
	}
	
	/**
	 Creats a URL from a filename path found in the database
	 */
	static func createURL(dbPath: String) -> URL {
		URL(fileURLWithPath: NSString(string: dbPath).expandingTildeInPath)
	}
}

enum DatabaseMessageRow {
	case message(ConversationItem)
	case modifier(ModifierInfo)
}

struct EditedUnsentMessageStatus {
	let editHistory: [String]
	let isUnsent: Bool
}
