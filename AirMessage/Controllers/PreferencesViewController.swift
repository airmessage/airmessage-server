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
	
	@IBOutlet weak var buttonSignOut: NSButton!
	@IBOutlet weak var labelSignOut: NSTextField!
	
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
		
		//Update "sign out" button text
		if PreferencesManager.shared.accountType == .direct {
			buttonSignOut.title = NSLocalizedString("action.switch_to_account", comment: "")
			labelSignOut.stringValue = NSLocalizedString("message.preference.account_manual", comment: "")
		} else if PreferencesManager.shared.accountType == .connect {
			buttonSignOut.title = NSLocalizedString("action.sign_out", comment: "")
			labelSignOut.stringValue = String(format: NSLocalizedString("message.preference.account_connect", comment: ""), PreferencesManager.shared.connectEmailAddress ?? "nil")
		}
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.preferences", comment: "")
		
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
				alert.messageText = NSLocalizedString("message.enter_server_port", comment: "")
			} else {
				alert.messageText = String(format: NSLocalizedString("message.invalid_server_port", comment: ""), inputPort.stringValue)
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
			//Make sure the server is running
			if(NSApplication.shared.delegate as! AppDelegate).currentServerState == .running {
				//Restart the server
				ConnectionManager.shared.stop()
				ConnectionManager.shared.setProxy(DataProxyTCP(port: inputPortValue))
				ConnectionManager.shared.start()
			}
		}
		
		//Start or stop update check timer
		if checkboxAutoUpdate.state == .on {
			UpdateHelper.startUpdateTimer()
		} else {
			UpdateHelper.stopUpdateTimer()
		}
		
		//Close window
		view.window!.close()
	}
	
	@IBAction func onClickSignOut(_ sender: NSButton) {
		let alert = NSAlert()
		if PreferencesManager.shared.accountType == .direct {
			alert.messageText = NSLocalizedString("message.reset.title.direct", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.switch_to_account", comment: ""))
		} else {
			alert.messageText = NSLocalizedString("message.reset.title.connect", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.sign_out", comment: ""))
		}
		alert.informativeText = NSLocalizedString("message.reset.subtitle", comment: "")
		alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: ""))
		alert.beginSheetModal(for: view.window!) { response in
			if response != .alertFirstButtonReturn {
				return
			}
			
			//Reset the server
			resetServer()
			
			//Close the preferences window
			self.view.window!.close()
			
			//Show the onboarding window
            OnboardingViewController.open()
		}
	}
	
	@IBAction func onClickReceiveBetaUpdates(_ sender: NSButton) {
		if sender.state == .on {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("message.beta_enrollment.title", comment: "")
			alert.informativeText = NSLocalizedString("message.beta_enrollment.description", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.receive_beta_updates", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: ""))
			alert.beginSheetModal(for: view.window!) { response in
				if response == .alertSecondButtonReturn {
					sender.state = .off
				}
			}
		} else {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("message.beta_unenrollment.title", comment: "")
			alert.informativeText = NSLocalizedString("message.beta_unenrollment.description", comment: "")
			alert.beginSheetModal(for: view.window!)
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
