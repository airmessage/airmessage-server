//
//  ViewControllerOnboarding.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-03.
//

import AppKit

func showOnboarding() {
	let storyboard = NSStoryboard(name: "Main", bundle: nil)
	let windowController = storyboard.instantiateController(withIdentifier: "Onboarding") as! NSWindowController
	windowController.showWindow(nil)
}

class OnboardingViewController: NSViewController {
	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
	}

	override func viewWillAppear() {
		let window = view.window!
		window.isMovableByWindowBackground = true
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "PasswordEntry" {
			let passwordEntry = segue.destinationController as! PasswordEntryViewController
			
			//Password is required for manual setup
			passwordEntry.isRequired = true
			passwordEntry.onSubmit = { [weak self] password in
				//Save password
				PreferencesManager.shared.password = password
				
				//Mark setup as complete
				PreferencesManager.shared.accountType = .direct
				PreferencesManager.shared.serverPort = defaultServerPort
				
				//Start server
				launchServer()
				
				//Close window
				if let self = self {
					self.view.window!.close()
				}
			}
		} else if segue.identifier == "AccountConnect" {
			let accountConnect = segue.destinationController as! AccountConnectViewController
			
			accountConnect.onAccountConfirm = { [weak self] refreshToken in
				//Save refresh token
				PreferencesManager.shared.refreshToken = refreshToken
				
				//Mark setup as complete
				PreferencesManager.shared.accountType = .connect
				
				//Start server
				launchServer()
				
				//Close window
				if let self = self {
					self.view.window!.close()
				}
			}
		}
	}
}

