//
//  ClientRegistration.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-08-01.
//

import Foundation

@objcMembers public class ClientRegistration: NSObject {
	let installationID: String
	let clientName: String
	let platformID: String
	
	public init(installationID: String, clientName: String, platformID: String) {
		self.installationID = installationID
		self.clientName = clientName
		self.platformID = platformID
		super.init()
	}
}