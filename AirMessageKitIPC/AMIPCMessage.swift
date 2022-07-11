//
//  AMIPCMessage.swift
//  AirMessageKitIPC
//
//  Created by Cole Feuer on 2022-07-10.
//

import Foundation

public struct AMIPCMessage: Codable {
	private static var nextID: UInt32 = 0
	
	public let id: UInt32
	public let payload: AMIPCMessagePayload
	
	public init(withPayload payload: AMIPCMessagePayload) {
		//Pick an unused ID
		id = AMIPCMessage.nextID
		AMIPCMessage.nextID += 1
		
		self.payload = payload
	}
	
	///Decodes a port message to an AirMessage IPC message
	public static func fromPortMessage(_ portMessage: PortMessage) throws -> AMIPCMessage {
		//Make sure the message has components
		guard let components = portMessage.components else {
			throw AMIPCMessageError.nilData
		}
		
		//Make sure the message has a single component
		guard components.count == 1 else {
			throw AMIPCMessageError.emptyData
		}
		
		//Make sure the message's component is data
		guard let componentData = components[0] as? Data else {
			throw AMIPCMessageError.dataFormat
		}
		
		//Decode the message data to an AMIPCMessage
		return try PropertyListDecoder().decode(AMIPCMessage.self, from: componentData)
	}
	
	///Encodes this message to Data
	public func encodeToData() throws -> Data {
		return try PropertyListEncoder().encode(self)
	}
}

public enum AMIPCMessagePayload: Codable {
	//Common response types
	case connected
	case ok
	case error(message: String?)
	
	case sendMessage(message: String, chat: String)
}

public enum AMIPCMessageError: Error {
	case nilData
	case emptyData
	case dataFormat
}
