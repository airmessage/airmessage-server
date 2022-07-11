//
//  TestXPC.swift
//  AirMessageKitTestClient
//
//  Created by Cole Feuer on 2022-07-10.
//

import Foundation

@objc protocol TestXPCProtocol {
	func upperCaseString(_ string: String, withReply reply: @escaping (String) -> Void)
}
