//
//  AutomationAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-11.
//

import Foundation
import AppKit

class AutomationAccessViewController: NSViewController {
	@IBOutlet weak var imageView: NSImageView!
	
	public var onDone: (() -> Void)?
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.automation_access", comment: "")
		
		//Update the image
		if #available(macOS 13.0, *) {
			imageView.image = NSImage(named: "AutomationAccess-13")
		} else {
			imageView.image = NSImage(named: "AutomationAccess")
		}
	}
	
	@IBAction func onOpenAutomationAccess(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
	}
	
	@IBAction func onClickDone(_ sender: Any) {
		view.window!.close()
		onDone?()
	}
}
