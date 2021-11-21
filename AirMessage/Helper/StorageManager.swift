//
//  StorageManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-15.
//

import Foundation

class StorageManager {
	/**
	 Gets the application storage directory
	 This call will create the directory if it doesn't exist
	 */
	static var storageDirectory: URL = {
		let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
		let appDir = applicationSupport.appendingPathComponent("AirMessage")
		try! FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
		
		return appDir
	}()
}
