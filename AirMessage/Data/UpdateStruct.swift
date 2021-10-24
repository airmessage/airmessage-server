//
// Created by Cole Feuer on 2021-10-03.
//

import Foundation

class UpdateStruct: NSObject {
	@objc let id: Int
	@objc let protocolRequirement: [Int]
	@objc let versionCode: Int
	@objc let versionName: String
	@objc let notes: String
	@objc let downloadURL: URL
	@objc let downloadExternal: Bool
	
	init(id: Int, protocolRequirement: [Int], versionCode: Int, versionName: String, notes: String, downloadURL: URL, downloadExternal: Bool) {
		self.id = id
		self.protocolRequirement = protocolRequirement
		self.versionCode = versionCode
		self.versionName = versionName
		self.notes = notes
		self.downloadURL = downloadURL
		self.downloadExternal = downloadExternal
	}
}
