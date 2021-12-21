//
// Created by Cole Feuer on 2021-10-03.
//

import Foundation

struct UpdateStruct {
	enum DownloadType {
		//This update can be downloaded and installed remotely
		case remote
		
		//This update can be downloaded and installed automatically,
		//but only if the user is present at the computer
		case local
		
		//This update will be downloaded through the browser, and must be
		//installed manually by the user
		case external
	}
	
	let id: Int32
	let protocolRequirement: [Int32]
	let versionCode: Int32
	let versionName: String
	let notes: String
	let downloadURL: URL
	let downloadType: DownloadType
}
