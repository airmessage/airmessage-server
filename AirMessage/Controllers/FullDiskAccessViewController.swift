//
//  FullDiskAccessViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-11.
//

import Foundation
import AppKit

class FullDiskAccessViewController: NSViewController {
	/*
	Older versions of OS X don't support drag-and-drop for file URLs
	*/
	@IBOutlet weak var yosemiteText: NSView! //OS X 10.10 to 10.12
	@IBOutlet weak var highSierraText: NSView! //OS X 10.13+
	@IBOutlet weak var highSierraDraggable: NSView! //OS X 10.13+
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		if #available(macOS 10.13, *) {
			yosemiteText.isHidden = true
		} else {
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
