//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class ClientConnection: Hashable {
	var id: Int32
	
	struct Registration {
		/**
		 * The installation ID of this instance
		 * Used for blocking multiple connections from the same client
		 */
		let installationID: String
		
		/**
		 * A human-readable name for this client
		 * Used when displaying connected clients to the user
		 * Examples:
		 * - Samsung Galaxy S20
		 * - Firefox 75
		 */
		let clientName: String
		
		/**
		 * The ID of the platform this device is running on
		 * Examples:
		 * - "android" (AirMessage for Android)
		 * - "google chrome" (AirMessage for web)
		 * - "windows" (AirMessage for Windows)
		 */
		let platformID: String
	}
	//Registration information for this client, once it's completed its handshake with the server
	var registration: Registration?
	
	//The current awaited transmission check for this client
	var transmissionCheck: Data?
	
	//Whether this client is connected. Set to false when the client disconnects.
	var isConnected: Bool = true
	
	init(id: Int32) {
		self.id = id
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
	
	static func ==(lhs: ClientConnection, rhs: ClientConnection) -> Bool {
		lhs.id == lhs.id
	}
}