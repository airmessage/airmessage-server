//
//  SystemBridge.swift
//  AirMessage
//
//  Created by Cole Feuer on 2022-07-10.
//

import Foundation
import IMCore11

class SystemBridge {
	static func sendMessage(_ message: String, toChat chat: String) {
		guard let chat = IMChatRegistry.sharedInstance().existingChat(withGUID: chat) else { return }
		
		let message = IMMessage.instantMessage(withText: NSAttributedString(string: "Hello"), flags: 1048581, threadIdentifier: nil)
		
		chat.sendMessage(message)
	}
}
