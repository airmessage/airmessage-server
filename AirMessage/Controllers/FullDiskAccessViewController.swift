//
//  FullDiskAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-11.
//

import Foundation
import AppKit

class FullDiskAccessViewController: NSViewController {
	@IBOutlet weak var imageView: NSImageView!
	
	//macOS 13 doesn't have a lock in System Settings
	@IBOutlet weak var lockText: NSView! //OS X 10.10 to 12
	
	/*
	Older versions of OS X don't support drag-and-drop for file URLs
	*/
	@IBOutlet weak var yosemiteText: NSView! //OS X 10.10 to 10.12
	@IBOutlet weak var highSierraText: NSView! //OS X 10.13+
	@IBOutlet weak var highSierraDraggable: NSView! //OS X 10.13+
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		//Use instructions for System Settings on macOS 13+
		if #available(macOS 13.0, *) {
			imageView.image = NSImage(named: "FullDiskAccess-13")
			lockText.isHidden = true
			yosemiteText.isHidden = true
		} else if #available(macOS 10.13, *) {
			yosemiteText.isHidden = true
		} else {
			//Dragging isn't supported
			highSierraText.isHidden = true
			highSierraDraggable.isHidden = true
		}
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.full_disk_access", comment: "")
	}
	
	@IBAction func onOpenFullDiskAccess(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
	}
}
