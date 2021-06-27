//
//  PasswordEntry.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import Cocoa

class PasswordEntry: NSViewController, NSTextFieldDelegate {
	@IBOutlet weak var secureField: NSSecureTextField!
	@IBOutlet weak var plainField: NSTextField!
	
	@IBOutlet weak var strengthLabel: NSTextField!
	@IBOutlet weak var passwordToggle: NSButton!
	
	@IBOutlet weak var confirmButton: NSButton!
	
	var currentTextField: NSTextField!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		secureField.delegate = self
		plainField.delegate = self
		
		currentTextField = secureField
		
		confirmButton.isEnabled = !secureField.stringValue.isEmpty
		
		//Perform initial UI update
		updateUI()
	}
	
	@IBAction func onPasswordVisibilityClick(_ sender: NSButton) {
		//Toggle password visibility
		if sender.state == .on {
			secureField.isHidden = true
			plainField.isHidden = false
			plainField.stringValue = secureField.stringValue
			plainField.becomeFirstResponder()
			
			currentTextField = plainField
		} else {
			secureField.isHidden = false
			plainField.isHidden = true
			secureField.stringValue = plainField.stringValue
			secureField.becomeFirstResponder()
			
			currentTextField = secureField
		}
	}
	
	func getText() -> String {
		return currentTextField.stringValue
	}
	
	func updateUI() {
		//Disable the button if there is no password
		confirmButton.isEnabled = !getText().isEmpty
		
		//Update the password strength label
		strengthLabel.stringValue = String(format: NSLocalizedString("passwordstrength", comment: ""), getPasswordStrengthLabel(calculatePasswordStrength(getText())))
	}

	
	func controlTextDidChange(_ obj: Notification) {
		//let textField = obj.object as! NSTextField
		updateUI()
	}
}
