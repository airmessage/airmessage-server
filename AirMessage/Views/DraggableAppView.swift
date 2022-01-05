//
//  DraggableAppView.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation
import AppKit

class DraggableAppView: NSImageView {
	override func mouseDown(with event: NSEvent) {
		guard #available(macOS 10.13, *) else { return }
		
		let url = Bundle.main.resourceURL!
		let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
		
		let pasteboardItem = NSPasteboardItem()
		pasteboardItem.setString(path, forType: .fileURL)
		
		let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
		draggingItem.setDraggingFrame(bounds, contents: Bundle.main.image(forResource: "AppIconResource")!)
		
		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}
}

extension DraggableAppView: NSDraggingSource {
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		.copy
	}
}
