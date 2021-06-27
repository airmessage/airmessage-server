//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import Cocoa
import os

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	var statusBarItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
	private let version = "4.0"
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		//guard let statusButton = statusBarItem.button else { return }
		//statusButton.title = "Advanced Clock"
		
		//let defaultLog = Logger()
		print("Starting AirMessage Server version \(version)")
	}
	
	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}
}