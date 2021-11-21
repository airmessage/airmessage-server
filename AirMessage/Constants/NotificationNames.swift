//
//  NotificationNames.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-14.
//

import Foundation

class NotificationNames {
	static let updateUIState = NSNotification.Name("updateUIState")
	static let updateUIStateParam = "state"
	
	static let updateConnectionCount = NSNotification.Name("updateConnectionCount")
	static let updateConnectionCountParam = "count"
	
	static let signOut = NSNotification.Name("signOut")
	
	/**
	 Posts the UI state update to `NotificationCenter` in a thread-safe manner
	 */
	static func postUpdateUIState(_ state: ServerState) {
		runOnMainAsync {
			NotificationCenter.default.post(name: NotificationNames.updateUIState, object: nil, userInfo: [NotificationNames.updateUIStateParam: state.rawValue])
		}
	}
}
