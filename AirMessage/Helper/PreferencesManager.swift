//
// Created by Cole Feuer on 2021-06-27.
//

import Foundation
import KeychainAccess

let defaultServerPort = 1359

class PreferencesManager: NSObject {
	private override init() {}
	
	public static let shared = PreferencesManager()
	@objc class func getShared() -> PreferencesManager { shared }
	
	private let keychain = Keychain(service: "AirMessage")
	
	// MARK: UserDefaults
	
	private enum UDKeys: String, CaseIterable {
		case serverPort
		case checkUpdates
		case betaUpdates
		case accountType
	}
	
	@objc var serverPort: Int {
		get {
			let port = UserDefaults.standard.integer(forKey: UDKeys.serverPort.rawValue)
			return port == 0 ? defaultServerPort : port
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.serverPort.rawValue)
		}
	}
	
	var checkUpdates: Bool {
		get {
			UserDefaults.standard.bool(forKey: UDKeys.checkUpdates.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.checkUpdates.rawValue)
		}
	}
	
	var betaUpdates: Bool {
		get {
			UserDefaults.standard.bool(forKey: UDKeys.betaUpdates.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.betaUpdates.rawValue)
		}
	}
	
	@objc var accountType: AccountType {
		get {
			if UserDefaults.standard.object(forKey: UDKeys.accountType.rawValue) != nil {
				return AccountType.init(rawValue: UserDefaults.standard.integer(forKey: UDKeys.accountType.rawValue)) ?? AccountType.unknown
			} else {
				return AccountType.unknown
			}
		}
		set(newValue) {
			UserDefaults.standard.set(newValue.rawValue, forKey: UDKeys.accountType.rawValue)
		}
	}
	
	// MARK: Keychain
	
	private enum KeychainKeys: String, CaseIterable {
		case password = "airmessage-password"
		case installationID = "airmessage-installation"
	}
	
	@objc var password: String? {
		get {
			keychain[KeychainKeys.password.rawValue]
		}
		set(newValue) {
			keychain[KeychainKeys.password.rawValue] = newValue
		}
	}
	
	@objc var installationID: String {
		get {
			if let existingID = keychain[KeychainKeys.installationID.rawValue] {
				return existingID
			} else {
				let newID = UUID().uuidString
				keychain[KeychainKeys.installationID.rawValue] = newID
				return newID
			}
		}
	}
}
