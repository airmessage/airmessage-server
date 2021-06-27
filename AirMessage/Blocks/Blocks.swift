enum MessageStateCode: Int {
	case idle = 0
	case sent = 1
	case delivered = 2
	case read = 3
}
enum MessageErrorCode: Int {
	case ok = 0
	case unknown = 1 //Unknown error code
	case network = 2 //Network error
	case unregistered = 3 //Not registered with iMessage
}

enum GroupActionType: Int {
	case unknown = 0
	case join = 1
	case leave = 2
}

protocol Block {
	func writeObject()
}

struct ConversationInfo: Block {
	let guid: String
	let available: Bool
	let service: String
	let name: String
	let members: [String]
	
	init(guid: String, available: Bool, service: String, name: String, members: [String]) {
		self.guid = guid
		self.available = available
		self.service = service
		self.name = name
		self.members = members
	}
	
	func writeObject() {
	
	}
}

struct LiteConversationInfo: Block {
	let guid: String
	let service: String
	let name: String
	let members: [String]
	let previewDate: Int64
	let previewSender: String
	let previewText: String
	let previewSendStyle: String?
	let previewAttachments: [String]
	
	init(guid: String, service: String, name: String, members: [String], previewDate: Int64, previewSender: String, previewText: String, previewSendStyle: String?, previewAttachments: [String]) {
		self.guid = guid
		self.service = service
		self.name = name
		self.members = members
		self.previewDate = previewDate
		self.previewSender = previewSender
		self.previewText = previewText
		self.previewSendStyle = previewSendStyle
		self.previewAttachments = previewAttachments
	}
	
	func writeObject() {
	
	}
}

protocol ConversationItem: Block {
	var itemType: Int { get }
	
	var serverID: Int64 { get }
	var guid: String { get }
	var chatGUID: String { get }
	var date: Int64 { get }
}

class MessageInfo: ConversationItem {
	let itemType = 0
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	let text: String?
	let subject: String?
	let sender: String?
	var attachments: [AttachmentInfo]
	var stickers: [StickerModifierInfo]
	var tapbacks: [TapbackModifierInfo]
	let sendEffect: String?
	let stateCode: MessageStateCode
	let errorCode: MessageErrorCode
	let dateRead: Int64?
	
	init(serverID: Int64, guid: String, chatGUID: String, date: Int64, text: String?, subject: String?, sender: String?, attachments: [AttachmentInfo], stickers: [StickerModifierInfo], tapbacks: [TapbackModifierInfo], sendEffect: String?, stateCode: MessageStateCode, errorCode: MessageErrorCode, dateRead: Int64?) {
		self.serverID = serverID
		self.guid = guid
		self.chatGUID = chatGUID
		self.date = date
		self.text = text
		self.subject = subject
		self.sender = sender
		self.attachments = attachments
		self.stickers = stickers
		self.tapbacks = tapbacks
		self.sendEffect = sendEffect
		self.stateCode = stateCode
		self.errorCode = errorCode
		self.dateRead = dateRead
	}
	
	func writeObject() {
	}
}

struct GroupActionInfo: ConversationItem {
	let itemType = 1
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	let agent: String?
	let other: String?
	let type: GroupActionType
	
	init(serverID: Int64, guid: String, chatGUID: String, date: Int64, agent: String?, other: String?, type: GroupActionType) {
		self.serverID = serverID
		self.guid = guid
		self.chatGUID = chatGUID
		self.date = date
		self.agent = agent
		self.other = other
		self.type = type
	}
	
	func writeObject() {
	}
}

struct ChatRenameActionInfo: ConversationItem {
	let itemType = 2
	
	let serverID: Int64
	let guid: String
	let chatGUID: String
	let date: Int64
	
	let agent: String?
	let newChatName: String?
	
	init(serverID: Int64, guid: String, chatGUID: String, date: Int64, agent: String?, newChatName: String?) {
		self.serverID = serverID
		self.guid = guid
		self.chatGUID = chatGUID
		self.date = date
		self.agent = agent
		self.newChatName = newChatName
	}
	
	func writeObject() {
	}
}

struct AttachmentInfo: Block {
	let guid: String
	let name: String
	let type: String?
	let size: Int64
	let checksum: [UInt8]?
	let sort: Int64
	
	init(guid: String, name: String, type: String?, size: Int64, checksum: [UInt8]?, sort: Int64) {
		self.guid = guid
		self.name = name
		self.type = type
		self.size = size
		self.checksum = checksum
		self.sort = sort
	}
	
	func writeObject() {
	}
}

class ModifierInfo: Block {
	var itemType: Int { -1 }
	let messageGUID: String
	
	fileprivate init(messageGUID: String) {
		self.messageGUID = messageGUID
	}
	
	func writeObject() {
		//packer.packInt(state);
		//packer.packLong(dateRead);
	}
}

class ActivityStatusModifierInfo: ModifierInfo {
	override var itemType: Int {0}
	
	let state: MessageStateCode
	let dateRead: Int64?
	
	init(messageGUID: String, state: MessageStateCode, dateRead: Int64?) {
		self.state = state
		self.dateRead = dateRead
		super.init(messageGUID: messageGUID)
	}
	
	override func writeObject() {
		super.writeObject()
	}
}

class StickerModifierInfo: ModifierInfo {
	override var itemType: Int {1}
	
	let serverID: Int64
	let messageIndex: Int
	let fileGUID: String
	let sender: String?
	let date: Int64
	let data: [UInt8]
	let type: String
	
	init(messageGUID: String, serverID: Int64, messageIndex: Int, fileGUID: String, sender: String?, date: Int64, data: [UInt8], type: String) {
		self.serverID = serverID
		self.messageIndex = messageIndex
		self.fileGUID = fileGUID
		self.sender = sender
		self.date = date
		self.data = data
		self.type = type
		super.init(messageGUID: messageGUID)
	}
	
	override func writeObject() {
		super.writeObject()
	}
}

class TapbackModifierInfo: ModifierInfo {
	override var itemType: Int {2}
	
	let serverID: Int64
	let messageIndex: Int
	let sender: String?
	let isAddition: Bool
	let tapbackType: Int
	
	init(messageGUID: String, serverID: Int64, messageIndex: Int, sender: String?, isAddition: Bool, tapbackType: Int) {
		self.serverID = serverID
		self.messageIndex = messageIndex
		self.sender = sender
		self.isAddition = isAddition
		self.tapbackType = tapbackType
		super.init(messageGUID: messageGUID)
	}
	
	override func writeObject() {
		super.writeObject()
	}
}