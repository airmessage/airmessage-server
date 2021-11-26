//
//  AutomationAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-11.
//

import Foundation
import AppKit

class AutomationAccessViewController: NSViewController {
	public var onDone: (() -> Void)?
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.automation_access", comment: "")
	}
	
	@IBAction func onOpenAutomationAccess(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
	}
	
	@IBAction func onClickDone(_ sender: Any) {
		view.window!.close()
		onDone?()
	}
}
