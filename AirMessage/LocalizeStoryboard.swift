//
//  LocalizeStoryboard.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-26.
//

import Foundation
import AppKit

extension NSTextField {
	@IBInspectable var localizedText: String {
		set(key) {
			stringValue = NSLocalizedString(key, comment: "")
		}
		
		get {
			stringValue
		}
	}
}

extension NSButton {
	@IBInspectable var localizedText: String {
		set(key) {
			title = NSLocalizedString(key, comment: "")
		}
		
		get {
			title
		}
	}
}

extension NSMenuItem {
	@IBInspectable var localizedText: String {
		set(key) {
			title = NSLocalizedString(key, comment: "")
		}
		
		get {
			title
		}
	}
}
