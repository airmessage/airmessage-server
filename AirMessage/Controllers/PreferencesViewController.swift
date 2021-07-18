//
//  ViewControllerPreferences.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-03.
//

import Foundation
import AppKit

class PreferencesViewController: NSViewController {
	@IBOutlet weak var inputPort: NSTextField!
	@IBOutlet weak var checkboxAutoUpdate: NSButton!
	@IBOutlet weak var checkboxBetaUpdate: NSButton!
	
	override func viewWillAppear() {
		super.viewWillAppear()
		preferredContentSize = view.fittingSize
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		//Load control values
		inputPort.stringValue = String(PreferencesManager.shared.serverPort)
		inputPort.formatter = PortFormatter()
		
		checkboxAutoUpdate.state = PreferencesManager.shared.checkUpdates ? .on : .off
		
		checkboxBetaUpdate.state = PreferencesManager.shared.betaUpdates ? .on : .off
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Focus app
		NSApp.activate(ignoringOtherApps: true)
	}
	
	@IBAction func onClickClose(_sender: NSButton) {
		//Close window
		view.window!.close()
	}
	
	@IBAction func onClickOK(_ sender: NSButton) {
		//Validate port input
		guard let inputPortValue = Int(inputPort.stringValue),
			  inputPortValue >= 1024 && inputPortValue <= 65535 else {
			let alert = NSAlert()
			alert.alertStyle = .critical
			if inputPort.stringValue.isEmpty {
				alert.messageText = "Please enter a server port"
			} else {
				alert.messageText = "\(inputPort.stringValue) cannot be used as a server port"
			}
			alert.beginSheetModal(for: view.window!)
			return
		}
		
		let originalPort = PreferencesManager.shared.serverPort
		
		//Save changes to disk
		PreferencesManager.shared.serverPort = inputPortValue
		PreferencesManager.shared.checkUpdates = checkboxAutoUpdate.state == .on
		PreferencesManager.shared.betaUpdates = checkboxBetaUpdate.state == .on
		
		//Restart the server if the port changed
		if originalPort != inputPortValue {
			launchServer()
		}
		
		//Close window
		view.window!.close()
	}
	
	@IBAction func onClickSwitchAccount(_ sender: NSButton) {
		let alert = NSAlert()
		alert.messageText = "Do you want to reconfigure AirMessage Server?"
		alert.informativeText = "Until you set up AirMessage Server again, you won't be able to receive messages on any AirMessage devices."
		alert.addButton(withTitle: "Switch to Account")
		alert.addButton(withTitle: "Cancel")
		alert.beginSheetModal(for: view.window!) { response in
			if response != .alertFirstButtonReturn {
				return
			}
			
			//Reset the server
			resetServer()
			
			//Close the preferences window
			self.view.window!.close()
			
			//Show the onboarding window
			showOnboarding()
		}
	}
	
	
	@IBAction func onClickReceiveBetaUpdates(_ sender: NSButton) {
		if sender.state == .on {
			let alert = NSAlert()
			alert.messageText = "Do you want to receive beta updates?"
			alert.informativeText = "Beta updates may be unstable, and may also require you to be enrolled in the beta program for AirMessage for Android."
			alert.addButton(withTitle: "Receive Beta Updates")
			alert.addButton(withTitle: "Cancel")
			alert.beginSheetModal(for: view.window!) { response in
				if response == .alertSecondButtonReturn {
					sender.state = .off
				}
			}
		}
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "PasswordEntry" {
			let passwordEntry = segue.destinationController as! PasswordEntryViewController
			
			//Password is required for manual setup, but not for AirMessage Cloud
			passwordEntry.isRequired = PreferencesManager.shared.accountType == .direct
			passwordEntry.onSubmit = { password in
				//Save password
				PreferencesManager.shared.password = password
			}
		}
	}
}

private class PortFormatter: NumberFormatter {
	override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<Optional<NSString>>?, errorDescription error: AutoreleasingUnsafeMutablePointer<Optional<NSString>>?) -> Bool {
		if partialString.isEmpty || //Allow empty string
				(Int(partialString) != nil && partialString.count <= 5) {
			return true
		} else {
			NSSound.beep()
			return false
		}
	}
}
