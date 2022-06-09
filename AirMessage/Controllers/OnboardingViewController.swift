//
//  ViewControllerOnboarding.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import Foundation
import AppKit

class OnboardingViewController: NSViewController {
    //Keep in memory for older versions of OS X
    private static var onboardingWindowController: NSWindowController!
    
    static func open() {
		//If we're already showing the window, just focus it
		if let window = onboardingWindowController?.window, window.isVisible {
			window.makeKeyAndOrderFront(self)
			NSApp.activate(ignoringOtherApps: true)
			return
		}
		
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Onboarding") as! NSWindowController
        windowController.showWindow(nil)
        onboardingWindowController = windowController
		NSApp.activate(ignoringOtherApps: true)
    }
    
	override func viewWillAppear() {
		let window = view.window!
		window.isMovableByWindowBackground = true
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
	}
	
	override func shouldPerformSegue(withIdentifier identifier: NSStoryboardSegue.Identifier, sender: Any?) -> Bool {
		if identifier == "PasswordEntry" {
			//Make sure Keychain is initialized
			do {
				try PreferencesManager.shared.initializeKeychain()
			} catch {
				KeychainManager.getErrorAlert(error).beginSheetModal(for: self.view.window!)
				return false
			}
			
			return true
		} else {
			return super.shouldPerformSegue(withIdentifier: identifier, sender: sender)
		}
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "PasswordEntry" {
			let passwordEntry = segue.destinationController as! PasswordEntryViewController
			
			//Password is required for manual setup
			passwordEntry.isRequired = true
			passwordEntry.onSubmit = { [weak self] password in
				guard let self = self else { return }
				//Save password and reset server port
				do {
					try PreferencesManager.shared.setPassword(password)
				} catch {
					KeychainManager.getErrorAlert(error).beginSheetModal(for: self.view.window!)
					return
				}
				PreferencesManager.shared.serverPort = defaultServerPort
				
				//Set the account type
				PreferencesManager.shared.accountType = .direct
				
				//Set the data proxy
				ConnectionManager.shared.setProxy(DataProxyTCP(port: defaultServerPort))
				
				//Disable setup mode
				NotificationNames.postUpdateSetupMode(false)
				
				//Start server
				launchServer()
				
				//Close window
				self.view.window!.close()
			}
		} else if segue.identifier == "AccountConnect" {
			let accountConnect = segue.destinationController as! AccountConnectViewController
			accountConnect.onAccountConfirm = { [weak self] userID, emailAddress in
				//Dismiss the connect view
				accountConnect.dismiss(self)
				
				//Save the user ID and email address
				PreferencesManager.shared.connectUserID = userID
				PreferencesManager.shared.connectEmailAddress = emailAddress
				
				//Set the account type
				PreferencesManager.shared.accountType = .connect
				
				//Disable setup mode
				NotificationNames.postUpdateSetupMode(false)
				
				//Run permissions check
				if checkServerPermissions() {
					//Connect to the database
					do {
						try DatabaseManager.shared.start()
					} catch {
						LogManager.log("Failed to start database: \(error)", level: .notice)
						ConnectionManager.shared.stop()
					}
					
					//Start listening for FaceTime calls
					if FaceTimeHelper.isSupported && PreferencesManager.shared.faceTimeIntegration {
						FaceTimeHelper.startIncomingCallTimer()
					}
				} else {
					//Disconnect and let the user resolve the error
					ConnectionManager.shared.stop()
				}
				
				//Close window
				if let self = self {
					self.view.window!.close()
				}
			}
		}
	}
}

