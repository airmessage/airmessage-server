//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	//Status bar
	private let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	@IBOutlet weak var menu: NSMenu!
	@IBOutlet weak var menuItemPrimary: NSMenuItem!
	@IBOutlet weak var menuItemSecondary: NSMenuItem!
	
	//UI state
	private var currentServerState = ServerState.setup
	private var currentClientCount = 0
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		LogManager.shared.log("Starting AirMessage Server version %@", type: .info, Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
		
		//Register status bar item
		statusBarItem.menu = menu
		let statusButton = statusBarItem.button!
		statusButton.image = NSImage(named:NSImage.Name("StatusBarIcon"))
		updateMenu()
		
		//Register notification center observers
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateUIState), name: NotificationNames.updateUIState, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateConnectionCount), name: NotificationNames.updateConnectionCount, object: nil)
		
		//Start JVM
		startJVM()
		
		//Show welcome window
		if PreferencesManager.shared.accountType == .unknown {
			showOnboarding()
			NSApp.activate(ignoringOtherApps: true)
		} else {
			//Start server
			launchServer()
		}
		
		//Prevent system from sleeping
		lockSystemSleep()
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		//Remove notification center observers
		NotificationCenter.default.removeObserver(self)
		
		//Stop JVM
		stopJVM()
		
		//Allow system to sleep
		releaseSystemSleep()
	}
	
	@objc private func onUpdateUIState(notification: NSNotification) {
		currentServerState = ServerState(rawValue: notification.userInfo![NotificationNames.updateUIStateParam] as! Int)!
		updateMenu()
	}
	
	@objc private func onUpdateConnectionCount(notification: NSNotification) {
		currentClientCount = notification.userInfo![NotificationNames.updateConnectionCountParam] as! Int
		updateMenu()
	}
	
	private func updateMenu() {
		menuItemPrimary.title = currentServerState.description
		
		if currentServerState.isError {
			switch currentServerState.recoveryType {
				case .retry:
					menuItemSecondary.title = NSLocalizedString("action.retry", comment: "")
					menuItemSecondary.action = #selector(onRestartServer)
					menuItemSecondary.isEnabled = true
				case .reauthenticate:
					menuItemSecondary.title = NSLocalizedString("action.reauthenticate", comment: "")
					menuItemSecondary.action = #selector(onReauthenticate)
					menuItemSecondary.isEnabled = true
				case .none:
					menuItemSecondary.isHidden = true
			}
		} else {
			menuItemSecondary.isEnabled = true
			menuItemSecondary.action = #selector(onOpenClientList)
			menuItemSecondary.title = String(format: NSLocalizedString("message.status.connected_count", comment: ""), currentClientCount)
		}
	}
	
	@objc private func onRestartServer() {
		launchServer()
	}
	
	@objc private func onReauthenticate() {
		
	}
	
	@objc private func onOpenClientList() {
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "ClientList") as! NSWindowController
		windowController.showWindow(nil)
	}
	
	@IBAction func onCheckForUpdates(_ sender: Any) {
		UpdateHelper.shared.checkUpdates(onError: {error in
			//Show an alert
			let alert = NSAlert()
			alert.alertStyle = .critical
			alert.messageText = error.localizedDescription
			alert.runModal()
		}, onUpdate: {updateData in
			if let updateData = updateData {
				//Update available, show window
				let storyboard = NSStoryboard(name: "Main", bundle: nil)
				let windowController = storyboard.instantiateController(withIdentifier: "SoftwareUpdate") as! NSWindowController
				let viewController = windowController.window!.contentViewController as! SoftwareUpdateViewController
				viewController.updateData = updateData
				
				windowController.showWindow(sender)
			} else {
				NSApp.activate(ignoringOtherApps: true)
				
				//Let the user know no new version is available
				let alert = NSAlert()
				alert.alertStyle = .informational
				alert.messageText = NSLocalizedString("message.noupdate.title", comment: "")
				alert.informativeText = String(
						format: NSLocalizedString("message.noupdate.description", comment: ""),
						Bundle.main.infoDictionary!["CFBundleName"] as! String,
						Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
				)
				alert.runModal()
			}
		})
	}
}
