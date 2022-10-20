//
//  AccessibilityAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-12-04.
//

import Foundation
import AppKit

class AccessibilityAccessViewController: NSViewController {
	@IBOutlet weak var imageView: NSImageView!
	
	//macOS 13 doesn't have a lock in System Settings
	@IBOutlet weak var lockText: NSView! //OS X 10.10 to 12
	
	public var onDone: (() -> Void)?
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.accessibility_access", comment: "")
		
		//Use instructions for System Settings on macOS 13+
		if #available(macOS 13.0, *) {
			imageView.image = NSImage(named: "AccessibilityAccess-13")
			lockText.isHidden = true
		} else {
			imageView.image = NSImage(named: "AccessibilityAccess")
		}
	}
	
	@IBAction func onOpenAccessibilityAccess(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
	}
	
	@IBAction func onClickDone(_ sender: Any) {
		view.window!.close()
		onDone?()
	}
}
