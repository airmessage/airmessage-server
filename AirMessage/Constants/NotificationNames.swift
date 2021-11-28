//
//  NotificationNames.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-14.
//

import Foundation

class NotificationNames {
	static let updateServerState = NSNotification.Name("updateServerState")
	static let updateServerStateParam = "state"
	
	static let updateSetupMode = NSNotification.Name("updateSetupMode")
	static let updateSetupModeParam = "isSetupMode"
	
	static let updateConnectionCount = NSNotification.Name("updateConnectionCount")
	static let updateConnectionCountParam = "count"
	
	static let authenticate = NSNotification.Name("authenticate")
	static let authenticateParam = "refreshToken"
	
	static let signOut = NSNotification.Name("signOut")
	
	/**
	 Posts a UI state update to `NotificationCenter` in a thread-safe manner
	 */
	static func postUpdateUIState(_ state: ServerState) {
		runOnMainAsync {
			NotificationCenter.default.post(name: NotificationNames.updateServerState, object: nil, userInfo: [NotificationNames.updateServerStateParam: state.rawValue])
		}
	}
	
	/**
	 Posts a setup mode update to `NotificationCenter` in a thread-safe manner
	 */
	static func postUpdateSetupMode(_ setupMode: Bool) {
		runOnMainAsync {
			NotificationCenter.default.post(name: NotificationNames.updateSetupMode, object: nil, userInfo: [NotificationNames.updateSetupModeParam: setupMode])
		}
	}
	
	/**
	 Posts a setup mode update to `NotificationCenter` in a thread-safe manner
	 */
	static func postUpdateConnectionCount(_ connectionCount: Int) {
		runOnMainAsync {
			NotificationCenter.default.post(name: NotificationNames.updateConnectionCount, object: nil, userInfo: [NotificationNames.updateConnectionCountParam: connectionCount])
		}
	}
	
	/**
	 Posts an authentication update to `NotificationCenter` in a thread-safe manner
	 */
	static func postAuthenticate(_ refreshToken: String) {
		runOnMainAsync {
			NotificationCenter.default.post(name: NotificationNames.authenticate, object: nil, userInfo: [NotificationNames.authenticateParam: refreshToken])
		}
	}
}
