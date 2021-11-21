//
//  ServerLaunch.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import AppKit

/**
 * Checks for launch permissions and starts the server, or restarts it if it's already running
 */
func launchServer() {
	//Check for setup and permissions before launching
	guard PreferencesManager.shared.accountType != .unknown && launchCheck() else {
		NotificationNames.postUpdateUIState(.setup)
		return
	}
	
	//Connect to the database
	do {
		try DatabaseManager.shared.resume()
	} catch {
		LogManager.shared.log("Failed to start database: %{public}", type: .notice, error.localizedDescription)
		NotificationNames.postUpdateUIState(.errorDatabase)
		return
	}
	
	//Start the server
	let proxy: DataProxy = DataProxyTCP()
	ConnectionManager.shared.start(proxy: proxy)
}

/**
 * Runs checks to test if the server has all the permissions it needs to work
 */
fileprivate func launchCheck() -> Bool {
	//Check for Apple Events access
	guard AppleScriptBridge.shared.checkPermissionsMessages() else {
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "AutomationAccess") as! NSWindowController
		(windowController.contentViewController as! AutomationAccessViewController).onDone = launchServer
		windowController.showWindow(nil)
		
		return false
	}
	
	//Check for Full Disk Access
	do {
		try FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/Library/Messages")
	} catch {
		LogManager.shared.log("Failed to read Messages directory: %s", type: .notice, error.localizedDescription)
		
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "FullDiskAccess") as! NSWindowController
		windowController.showWindow(nil)
		
		return false
	}
	
	return true
}

/**
* Stops the server and resets the state to setup
*/
func resetServer() {
	ConnectionManager.shared.stop()
	DatabaseManager.shared.cancel()
	PreferencesManager.shared.accountType = .unknown
}
