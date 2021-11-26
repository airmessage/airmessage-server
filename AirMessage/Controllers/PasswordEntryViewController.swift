//
//  PasswordEntry.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import AppKit

class PasswordEntryViewController: NSViewController {
	@IBOutlet weak var secureField: NSSecureTextField!
	@IBOutlet weak var plainField: NSTextField!
	
	@IBOutlet weak var strengthLabel: NSTextField!
	@IBOutlet weak var passwordToggle: NSButton!
	
	@IBOutlet weak var confirmButton: NSButton!
	
	private var currentTextField: NSTextField!
	
	public var isRequired = true
	public var onSubmit: ((String) -> Void)?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		secureField.delegate = self
		plainField.delegate = self
		
		currentTextField = secureField
		currentTextField.stringValue = PreferencesManager.shared.password
		
		confirmButton.isEnabled = !secureField.stringValue.isEmpty
		
		//Perform initial UI update
		updateUI()
	}
	
	@IBAction func onClickPasswordVisibility(_ sender: NSButton) {
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
	
	func updateUI() {
		//Disable the button if there is no password and the password is required
		confirmButton.isEnabled = !isRequired || !getText().isEmpty
		
		//Update the password strength label
		strengthLabel.stringValue = String(format: NSLocalizedString("label.password_strength", comment: ""), getPasswordStrengthLabel(calculatePasswordStrength(getText())))
	}
	
	func getText() -> String { currentTextField.stringValue }
	
	@IBAction func onClickConfirm(_ sender: NSButton) {
		onSubmit?(getText())
		
		dismiss(self)
	}
}

extension PasswordEntryViewController: NSTextFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		updateUI()
	}
}
