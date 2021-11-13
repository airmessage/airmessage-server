//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation

protocol WritableBlock {
	func write()
}

struct ConversationInfo {
	let guid: String
	let available: Bool
	let service: String
	let name: String?
	let members: [String]
}

struct LiteConversationInfo {
	let guid: String
	let service: String
	let name: String?
	let members: [String]
	
	let previewDate: Int64
	let previewSender: String?
	let previewText: String?
	let previewSendStyle: String?
	let previewAttachments: [String]
}

protocol ConversationItem {
	var serverID: Int64 {get}
	var guid: String {get}
	var chatGUID: String {get}
	var date: Int64 {get}
}

struct MessageInfo: ConversationItem {
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	static let itemType: Int32 = 0
	enum State: Int32 {
		case idle = 0
		case sent = 1
		case delivered = 2
		case read = 3
	}
	enum Error: Int32 {
		case ok = 0
		case unknown = 1 //Unknown error code
		case network = 2 //Network error
		case unregistered = 3 //Not registered with iMessage
	}
	
	let text: String?
	let subject: String?
	let sender: String?
	var attachments: [AttachmentInfo]
	var stickers: [StickerModifierInfo]
	var tapbacks: [TapbackModifierInfo]
	let sendEffect: String?
	let state: State
	let error: Error
	let dateRead: Int64
}

struct GroupActionInfo: ConversationItem {
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	static let itemType: Int32 = 1
	enum Subtype: Int32 {
		case unknown = 0
		case join = 1
		case leave = 2
	}
	
	let agent: String?
	let other: String?
	let subtype: Subtype
}

struct ChatRenameActionInfo: ConversationItem {
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	static let itemType: Int32 = 2
	
	let agent: String?
	let updatedName: String?
}

struct AttachmentInfo {
	let guid: String
	let name: String
	let type: String?
	let size: Int64
	let checksum: Data?
	let sort: Int64
}

protocol ModifierInfo {
	static var itemType: Int32 {get}
	var messageGUID: String {get}
}

struct ActivityStatusModifierInfo: ModifierInfo {
	static let itemType: Int32 = 0
	let messageGUID: String
	
	let state: MessageInfo.State
	let dateRead: Int64
}

struct StickerModifierInfo: ModifierInfo {
	static let itemType: Int32 = 1
	let messageGUID: String
	
	let messageIndex: Int32
	let fileGUID: String
	let sender: String?
	let date: Int64
	let data: Data
	let type: String
}

struct TapbackModifierInfo: ModifierInfo {
	static let itemType: Int32 = 2
	let messageGUID: String
	
	let messageIndex: Int32
	let sender: String?
	let isAddition: Bool
	let tapbackType: Int32
}