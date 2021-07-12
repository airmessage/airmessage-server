//
//  AppleScriptBridge.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-10.
//

import Foundation

class AppleScriptBridge: NSObject {
	private lazy var scriptTestAutomation = NSAppleScript.init(
			contentsOf: Bundle.main.url(forResource: "testPermissionsMessages", withExtension: "applescript", subdirectory: "AppleScriptSource")!,
			error: nil)!
	
	private override init() {
	}
	
	@objc public static let shared = AppleScriptBridge()
	
	@objc func checkPermissionsMessages() -> Bool {
		//Compile the script when this function is invoked, since this likely won't be called enough to be worth saving the compiled result for later
		let scriptTestAutomation = NSAppleScript.init(
				contentsOf: Bundle.main.url(forResource: "testPermissionsMessages", withExtension: "applescript", subdirectory: "AppleScriptSource")!,
				error: nil)!
		
		var scriptError: NSDictionary?
		let scriptResult = scriptTestAutomation.executeAndReturnError(&scriptError)
		return scriptResult != nil
	}
}
