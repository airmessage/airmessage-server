//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	private let appVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
	
	@IBOutlet weak var menu: NSMenu!
	@IBOutlet weak var firstMenuItem: NSMenuItem!
	
	var statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		let statusButton = statusBarItem.button!
		statusButton.image = NSImage(named:NSImage.Name("StatusBarIcon"))
		
		//let defaultLog = Logger()
		print("Starting AirMessage Server version \(appVersion)")
		
		if PreferencesManager.shared.accountType == .unknown {
			let storyboard = NSStoryboard(name: "Main", bundle: nil)
			let windowController = storyboard.instantiateController(withIdentifier: "Onboarding") as! NSWindowController
			windowController.showWindow(nil)
		}
		
		//Start server
		launchServer()
		
		//Start JVM
		startJVM()
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		if let menu = menu {
			statusBarItem.menu = menu
		}
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// Insert code here to tear down your application
	}
}
