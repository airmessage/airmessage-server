//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation

protocol BaseConversationInfo: Packable {
	var guid: String { get }
}

struct ConversationInfo: BaseConversationInfo {
	let guid: String
	let service: String
	let name: String?
	let members: [String]
	
	func pack(to packer: inout AirPacker) {
		packer.pack(string: guid)
		packer.pack(bool: true) //Conversation available
		packer.pack(string: service)
		packer.pack(optionalString: name)
		packer.pack(stringArray: members)
	}
}

struct UnavailableConversationInfo: BaseConversationInfo {
	let guid: String
	
	func pack(to packer: inout AirPacker) {
		packer.pack(string: guid)
		packer.pack(bool: false) //Conversation unavailable
	}
}

struct LiteConversationInfo: Packable {
	let guid: String
	let service: String
	let name: String?
	let members: [String]
	
	let previewDate: Int64
	let previewSender: String?
	let previewText: String?
	let previewSendStyle: String?
	let previewAttachments: [String]
	
	func pack(to packer: inout AirPacker) {
		packer.pack(string: guid)
		packer.pack(string: service)
		packer.pack(optionalString: name)
		packer.pack(stringArray: members)
		
		packer.pack(long: previewDate)
		packer.pack(optionalString: previewSender)
		packer.pack(optionalString: previewText)
		packer.pack(optionalString: previewSendStyle)
		packer.pack(stringArray: previewAttachments)
	}
}

protocol ConversationItem: Packable {
	static var itemType: Int32 {get}
	
	var serverID: Int64 { get }
	var guid: String { get }
	var chatGUID: String { get }
	var date: Int64 { get }
}

extension ConversationItem {
	func packBase(to packer: inout AirPacker) {
		packer.pack(int: Self.itemType)
		
		packer.pack(long: serverID)
		packer.pack(string: guid)
		packer.pack(string: chatGUID)
		packer.pack(long: date)
	}
}

struct MessageInfo: ConversationItem {
	static let itemType: Int32 = 0
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
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
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(optionalString: text)
		packer.pack(optionalString: subject)
		packer.pack(optionalString: sender)
		packer.pack(packableArray: attachments)
		packer.pack(packableArray: stickers)
		packer.pack(packableArray: tapbacks)
		packer.pack(optionalString: sendEffect)
		packer.pack(int: state.rawValue)
		packer.pack(int: error.rawValue)
		packer.pack(long: dateRead)
	}
}

struct GroupActionInfo: ConversationItem {
	static let itemType: Int32 = 1
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	enum Subtype: Int32 {
		case unknown = 0
		case join = 1
		case leave = 2
	}
	
	let agent: String?
	let other: String?
	let subtype: Subtype
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(optionalString: agent)
		packer.pack(optionalString: other)
		packer.pack(int: subtype.rawValue)
	}
}

struct ChatRenameActionInfo: ConversationItem {
	static let itemType: Int32 = 2
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	let agent: String?
	let updatedName: String?
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(optionalString: agent)
		packer.pack(optionalString: updatedName)
	}
}

struct AttachmentInfo: Packable {
	let guid: String
	let name: String
	let type: String?
	let size: Int64
	let checksum: Data?
	let sort: Int64
	let localURL: URL?
	
	func pack(to packer: inout AirPacker) {
		packer.pack(string: guid)
		packer.pack(string: name)
		packer.pack(optionalString: type)
		packer.pack(long: size)
		packer.pack(optionalPayload: checksum)
		packer.pack(long: sort)
	}
}

protocol ModifierInfo: Packable {
	static var itemType: Int32 { get }
	var messageGUID: String { get }
}

extension ModifierInfo {
	func packBase(to packer: inout AirPacker) {
		packer.pack(int: Self.itemType)
		packer.pack(string: messageGUID)
	}
}

struct ActivityStatusModifierInfo: ModifierInfo {
	static let itemType: Int32 = 0
	let messageGUID: String
	
	let state: MessageInfo.State
	let dateRead: Int64
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(int: state.rawValue)
		packer.pack(long: dateRead)
	}
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
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(int: messageIndex)
		packer.pack(string: fileGUID)
		packer.pack(optionalString: sender)
		packer.pack(long: date)
		packer.pack(payload: data)
		packer.pack(string: type)
	}
}

struct TapbackModifierInfo: ModifierInfo {
	static let itemType: Int32 = 2
	let messageGUID: String
	
	let messageIndex: Int32
	let sender: String?
	let isAddition: Bool
	let tapbackType: Int32
	
	func pack(to packer: inout AirPacker) {
		packBase(to: &packer)
		
		packer.pack(int: messageIndex)
		packer.pack(optionalString: sender)
		packer.pack(bool: isAddition)
		packer.pack(int: tapbackType)
	}
}
