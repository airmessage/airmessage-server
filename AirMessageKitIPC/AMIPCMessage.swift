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
	
	///Decodes this message from data
	public static func decodeFromData(_ data: Data) throws -> AMIPCMessage {
		try PropertyListDecoder().decode(AMIPCMessage.self, from: data)
	}
	
	///Encodes this message to Data
	public func encodeToData() throws -> Data {
		try PropertyListEncoder().encode(self)
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
