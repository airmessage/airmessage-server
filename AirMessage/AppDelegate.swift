//
//  AppDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import Foundation
import AppKit
import Sentry

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	//Status bar
	private var statusBarItem: NSStatusItem!
	private var menuItemPrimary: NSMenuItem!
	private var menuItemSecondary: NSMenuItem!
	private var menuItemPreferences: NSMenuItem!
	
	//UI state
	public var currentServerState = ServerState.stopped
	public var currentClientCount = 0
	public var isSetupMode = false
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		LogManager.log("Starting AirMessage Server version \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)", level: .info)
		
		//Initialize Sentry
		SentrySDK.start { options in
			#if DEBUG
				options.enabled = false
			#else
				options.enabled = true
			#endif
			options.enableSwizzling = false
			
			//Sentry uses a Let's Encrypt certificate, so we distribute their root certificate
			//ourselves so that older Macs still trust it
			options.urlSessionDelegate = URLSessionCompat.delegate
			
			options.dsn = Bundle.main.infoDictionary!["SENTRY_DSN"] as? String
		}
		
		//Initialize custom queues
		CustomQueue.register()
		
		//Initialize preferences
		PreferencesManager.shared.registerPreferences()
		
		//Register status bar item
		statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
		
		let statusButton = statusBarItem.button!
		statusButton.image = NSImage(named: NSImage.Name("StatusBarIcon"))
		
		let statusBarMenu = NSMenu()
		statusBarMenu.autoenablesItems = false
		menuItemPrimary = statusBarMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
		menuItemPrimary.isEnabled = false
		menuItemSecondary = statusBarMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
		statusBarMenu.addItem(NSMenuItem.separator())
		menuItemPreferences = statusBarMenu.addItem(withTitle: NSLocalizedString("action.preferences", comment: ""), action: #selector(onOpenPreferences), keyEquivalent: "")
		statusBarMenu.addItem(withTitle: NSLocalizedString("action.check_for_updates", comment: ""), action: #selector(onCheckForUpdates), keyEquivalent: "")
		statusBarMenu.addItem(NSMenuItem.separator())
		statusBarMenu.addItem(withTitle: NSLocalizedString("action.about_airmessage", comment: ""), action: #selector(onAboutApp), keyEquivalent: "")
		statusBarMenu.addItem(withTitle: NSLocalizedString("action.quit_airmessage", comment: ""), action: #selector(onQuitApp), keyEquivalent: "")
		statusBarItem.menu = statusBarMenu
		
		//Register notification center observers
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateServerState), name: NotificationNames.updateServerState, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateSetupMode), name: NotificationNames.updateSetupMode, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateConnectionCount), name: NotificationNames.updateConnectionCount, object: nil)
		
		//Set the data proxy
		let dataProxyRegistered = setDataProxyAuto()
		if !dataProxyRegistered {
			//Show welcome window
			isSetupMode = true
            OnboardingViewController.open()
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
		FaceTimeHelper.stopIncomingCallTimer()
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
	
	@objc private func onOpenPreferences() {
		PreferencesViewController.open()
	}
	
	@objc private func onRestartServer() {
		launchServer()
	}
	
	@objc private func onReauthenticate() {
		resetServer()
        OnboardingViewController.open()
	}
	
	@objc private func onOpenClientList() {
        ClientListViewController.open()
	}
	
	@objc private func onCheckForUpdates() {
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
						Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
				)
				alert.runModal()
			}
		})
	}
	
	@objc private func onAboutApp() {
		NSApplication.shared.orderFrontStandardAboutPanel(self)
	}
	
	@objc private func onQuitApp() {
		NSApplication.shared.terminate(self)
	}
}
