//
//  AppDelegate.swift
//  AirMessageKitTestClient
//
//  Created by Cole Feuer on 2022-07-10.
//

import Cocoa
import AirMessageKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	let context = AMKContext()
	
	func applicationDidFinishLaunching(_ aNotification: Notification) {
		context.launch()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		context.terminate()
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}
}

