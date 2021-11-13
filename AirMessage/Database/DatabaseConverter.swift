//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation
import SQLite

class DatabaseConverter {
	enum MessageItemType: Int {
		case message = 0
		case groupAction = 1
		case chatRename = 2
		case chatLeave = 3
	}
	
	static func processMessageRow(_ row: Statement.Element, withIndices indices: [String: Int], ofDB db: Connection) throws -> DatabaseMessageRow? {
		//Common message parameters
		let rowID = row[indices["message.ROWID"]!] as! Int64
		let guid = row[indices["message.guid"]!] as! String
		let chatGUID = row[indices["chat.guid"]!] as! String
		let date = row[indices["message.date"]!] as! Int64
		
		let sender = (row[indices["message.is_from_me"]!] as! Bool) ? nil : (row[indices["sender_handle.id"]!] as! String)
		let itemType = MessageItemType(rawValue: row[indices["message.item_type"]!] as! Int)
		
		if itemType == .message {
			if #available(macOS 10.12, *) {
				//Getting the association info
				let associatedMessage = row[indices["message.associated_message_guid"]!] as! String
				let associationType = row[indices["message.associated_message_type"]!] as! Int
				let associationIndex = row[indices["message.associated_message_range_location"]!] as! Int
				
				//Checking if there is an association
				if associationType != 0 {
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
						associatedMessageGUID = String(part[part.firstIndex(of: "/")!...])
					} else {
						//Unknown type
						LogManager.shared.log("Encountered unexpected association data: %{public}", type: .error, associatedMessage)
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
			let text = (row[indices["message.text"]!] as! String?)?
					//Replace some characters that can magically appear in messages
					.replacingOccurrences(of: "\u{FFFC}", with: "")
					.replacingOccurrences(of: "\u{FFFD}", with: "")
			let subject = row[indices["message.text"]!] as! String?
			let sendEffect: String?
			if #available(macOS 10.12, *) {
				sendEffect = row[indices["message.expressive_send_style_id"]!] as! String?
			} else {
				sendEffect = nil
			}
			let state = mapMessageStateCode(
					isSent: row[indices["message.is_sent"]!] as! Bool,
					isDelivered: row[indices["message.is_delivered"]!] as! Bool,
					isRead: row[indices["message.is_read"]!] as! Bool
			)
			let error = mapMessageErrorCode(row[indices["message.error"]!] as! Int)
			let dateRead = row[indices["message.date_read"]!] as! Int64
			let attachments = try fetchAttachments(ofMessage: rowID, withChecksum: sender != nil, ofDB: db)
			
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
					dateRead: convertDBTime(fromDB: dateRead)
			))
		} else if itemType == .groupAction {
			let other = row[indices["other_handle.id"]!] as! String?
			let actionType = mapGroupActionType(row[indices["message.group_action_type"]!] as! Int)
			
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
								  SELECT \(fields.joined(separator: ", "))
								  FROM message_attachment_join
								  JOIN attachment ON message_attachment_join.attachment_id = attachment.ROWID
								  WHERE message_attachment_join.message_id = ?
								  """, messageID)
		
		let indices = makeColumnIndexDict(stmt.columnNames)
		let attachments = stmt.compactMap { row -> AttachmentInfo? in
			//Ignore hidden attachments
			if #available(macOS 10.12, *), row[indices["attachment.hide_attachment"]!] as! Bool {
				return nil
			}
			
			//Ignore attachments with no transfer name
			guard row[indices["attachment.transfer_name"]!] != nil else {
				return nil
			}
			
			let guid = row[indices["attachment.guid"]!] as! String
			let name = row[indices["attachment.transfer_name"]!] as! String
			let type = row[indices["attachment.mime_type"]!] as! String
			let size = row[indices["attachment.total_bytes"]!] as! Int64
			let path = row[indices["attachment.filename"]!] as? String
			let checksum: Data?
			if withChecksum, let path = path {
				checksum = md5HashFile(url: URL(fileURLWithPath: path))
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
					sort: row
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
                                  SELECT attachment.guid, attachment.filename, attachment.mime_type
                                  FROM message_attachment_join
                                  JOIN attachment ON message_attachment_join.attachment_id = attachment.ROWID
                                  WHERE message_attachment_join.message_id = ?
                                  LIMIT 1
                                  """, messageID)
		let indices = makeColumnIndexDict(stmt.columnNames)
		guard let row = stmt.next(),
			  let filePath = row[indices["attachment.filename"]!],
			  var fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath as! String)),
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
	
	/**
 	 Converts a string array to a dictionary that maps the string value to its index
 	*/
	public static func makeColumnIndexDict(_ columnNames: [String]) -> [String: Int] {
		columnNames.enumerated().reduce(into: [String: Int]()) { dict, element in
			dict[element.element] = element.offset
		}
	}
	
	/**
	 Maps a series of boolean values from the database to a `MessageInfo.State`
	 */
	static func mapMessageStateCode(isSent: Bool, isDelivered: Bool, isRead: Bool) -> MessageInfo.State {
		if isSent {
			return .sent
		} else if isDelivered {
			return .delivered
		} else if isRead {
			return .read
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
}

enum DatabaseMessageRow {
	case message(ConversationItem)
	case modifier(ModifierInfo)
}
