//
//  NotificationNames.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-14.
//

import Foundation

class NotificationNames: NSObject {
	@objc public static let updateUIState = NSNotification.Name("updateUIState")
	@objc public static let updateUIStateParam = "state"
	
	@objc public static let updateConnectionCount = NSNotification.Name("updateConnectionCount")
	@objc public static let updateConnectionCountParam = "count"
	
	@objc public static let signOut = NSNotification.Name("signOut")
}
