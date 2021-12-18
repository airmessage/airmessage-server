//
//  AccessibilityAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-12-04.
//

import Foundation
import AppKit

class AccessibilityAccessViewController: NSViewController {
	public var onDone: (() -> Void)?
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.accessibility_access", comment: "")
	}
	
	@IBAction func onOpenAccessibilityAccess(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
	}
	
	@IBAction func onClickDone(_ sender: Any) {
		view.window!.close()
		onDone?()
	}
}
