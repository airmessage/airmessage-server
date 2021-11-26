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
	@IBOutlet weak var menuItemPreferences: NSMenuItem!
	
	//UI state
	public var currentServerState = ServerState.stopped
	public var currentClientCount = 0
	public var isSetupMode = false
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		LogManager.log("Starting AirMessage Server version \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)", level: .info)
		
		//Register status bar item
		statusBarItem.menu = menu
		let statusButton = statusBarItem.button!
		statusButton.image = NSImage(named:NSImage.Name("StatusBarIcon"))
		
		//Register notification center observers
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateServerState), name: NotificationNames.updateServerState, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateSetupMode), name: NotificationNames.updateSetupMode, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateConnectionCount), name: NotificationNames.updateConnectionCount, object: nil)
		
		//Set the data proxy
		let dataProxyRegistered = setDataProxyAuto()
		if !dataProxyRegistered {
			//Show welcome window
			isSetupMode = true
			showOnboarding()
			NSApp.activate(ignoringOtherApps: true)
		} else {
			//Start server
			launchServer()
		}
		
		//Update the menu
		updateMenu()
		
		//Prevent system from sleeping
		lockSystemSleep()
		
		//Start update timer
		if PreferencesManager.shared.checkUpdates {
			UpdateHelper.startUpdateTimer()
		}
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		//Remove notification center observers
		NotificationCenter.default.removeObserver(self)
		
		//Allow system to sleep
		releaseSystemSleep()
		
		//Disconnect
		ConnectionManager.shared.stop()
		DatabaseManager.shared.stop()
	}
	
	@objc private func onUpdateServerState(notification: NSNotification) {
		currentServerState = ServerState(rawValue: notification.userInfo![NotificationNames.updateServerStateParam] as! Int)!
		updateMenu()
	}
	
	@objc private func onUpdateSetupMode(notification: NSNotification) {
		isSetupMode = notification.userInfo![NotificationNames.updateSetupModeParam] as! Bool
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
		
		menuItemPreferences.isEnabled = !isSetupMode
	}
	
	@objc private func onRestartServer() {
		launchServer()
	}
	
	@objc private func onReauthenticate() {
		resetServer()
		showOnboarding()
	}
	
	@objc private func onOpenClientList() {
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "ClientList") as! NSWindowController
		windowController.showWindow(nil)
	}
	
	@IBAction func onCheckForUpdates(_ sender: Any) {
		UpdateHelper.checkUpdates(onError: {error in
			NSApp.activate(ignoringOtherApps: true)
			
			//Show an alert
			let alert = NSAlert()
			alert.alertStyle = .critical
			alert.messageText = NSLocalizedString("message.update.error.title", comment: "")
			alert.informativeText = error.localizedDescription
			alert.runModal()
		}, onUpdate: {update, isNew in
			//Show the window in the foreground
			UpdateHelper.showUpdateWindow(for: update, isNew: isNew, backgroundMode: false)
			
			//Show an alert if there's no new version
			if update == nil {
				NSApp.activate(ignoringOtherApps: true)
				
				let alert = NSAlert()
				alert.alertStyle = .informational
				alert.messageText = NSLocalizedString("message.update.uptodate.title", comment: "")
				alert.informativeText = String(
						format: NSLocalizedString("message.update.uptodate.description", comment: ""),
						Bundle.main.infoDictionary!["CFBundleName"] as! String,
						Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
				)
				alert.runModal()
			}
		})
	}
}
