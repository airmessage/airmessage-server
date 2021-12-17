//
//  ServerLaunch.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import AppKit

/**
 Automatically sets the most appropriate data proxy
 - Returns: Whether a data proxy was set
 */
func setDataProxyAuto() -> Bool {
	switch PreferencesManager.shared.accountType {
		case .direct:
			ConnectionManager.shared.setProxy(DataProxyTCP(port: PreferencesManager.shared.serverPort))
			return true
		case .connect:
			let installationID = PreferencesManager.shared.installationID
			guard let userID = PreferencesManager.shared.connectUserID else {
				LogManager.log("Couldn't set default data proxy - no Connect user ID", level: .notice)
				return false
			}
			ConnectionManager.shared.setProxy(DataProxyConnect(installationID: installationID, userID: userID))
			return true
		case .unknown:
			return false
	}
}

/**
 * Checks for launch permissions and starts the server, or restarts it if it's already running
 */
func launchServer() {
	//Check for setup and permissions before launching
	guard PreferencesManager.shared.accountType != .unknown && checkServerPermissions() else {
		NotificationNames.postUpdateUIState(.setup)
		return
	}
	
	//Connect to the database
	do {
		try DatabaseManager.shared.start()
	} catch {
		LogManager.log("Failed to start database: \(error)", level: .notice)
		NotificationNames.postUpdateUIState(.errorDatabase)
		return
	}
	
	//Start listening for FaceTime calls
	if FaceTimeHelper.isSupported && PreferencesManager.shared.faceTimeIntegration {
		FaceTimeHelper.startIncomingCallTimer()
	}
	
	//Start the server
	ConnectionManager.shared.start()
}

/**
 * Runs checks to test if the server has all the permissions it needs to work
 */
func checkServerPermissions() -> Bool {
	//Check for FaceTime Accessibility access
	if FaceTimeHelper.isSupported && PreferencesManager.shared.faceTimeIntegration {
		guard AppleScriptBridge.shared.checkPermissionsFaceTime() else {
			let storyboard = NSStoryboard(name: "Main", bundle: nil)
			let windowController = storyboard.instantiateController(withIdentifier: "AccessibilityAccess") as! NSWindowController
			(windowController.contentViewController as! AccessibilityAccessViewController).onDone = launchServer
			windowController.showWindow(nil)
			
			return false
		}
	}
	
	//Check for Messages Automation access
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
		LogManager.log("Failed to read Messages directory: \(error)", level: .info)
		
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
	PreferencesManager.shared.accountType = .unknown
	NotificationNames.postUpdateSetupMode(true)
	
	ConnectionManager.shared.stop()
	DatabaseManager.shared.stop()
}
