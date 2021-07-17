//
//  ServerLaunch.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import AppKit

func launchServer() {
	//Check for setup and permissions before launching
	guard PreferencesManager.shared.accountType != .unknown && launchCheck() else {
		NotificationCenter.default.post(name: NotificationNames.updateUIState, object: nil, userInfo: [NotificationNames.updateUIStateParam: ServerState.setup.rawValue])
		
		return
	}
	
	//Tell Java to start the server
	jniStartServer()
}

fileprivate func launchCheck() -> Bool {
	guard AppleScriptBridge.shared.checkPermissionsMessages() else {
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "AutomationAccess") as! NSWindowController
		(windowController.contentViewController as! AutomationAccessViewController).onDone = launchServer
		windowController.showWindow(nil)
		
		return false
	}
	
	do {
		print(try FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/Library/Messages"))
		//print(try FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/Downloads"))
	} catch {
		print("Unexpected error: \(error).")
		
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "FullDiskAccess") as! NSWindowController
		windowController.showWindow(nil)
		
		return false
	}
	
	return true
}
