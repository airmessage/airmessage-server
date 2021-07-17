//
// Created by Cole Feuer on 2021-06-27.
//

import Foundation

let defaultServerPort = 1359

class PreferencesManager: NSObject {
	private override init() {}
	
	public static let shared = PreferencesManager()
	@objc class func getShared() -> PreferencesManager { shared }
	
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
	
	private var passwordCache: String?
	private var installationIDCache: String?
	
	@objc var password: String {
		get {
			DispatchQueue.main.sync {
				if let passwordCache = passwordCache {
					return passwordCache
				} else {
					let keychainValue = try! KeychainManager.getValue(for: KeychainKeys.password.rawValue) ?? ""
					passwordCache = keychainValue
					return keychainValue
				}
			}
		}
		set(newValue) {
			DispatchQueue.main.async {
				try! KeychainManager.setValue(newValue, for: KeychainKeys.password.rawValue)
				self.passwordCache = newValue
			}
		}
	}
	
	@objc var installationID: String {
		get {
			DispatchQueue.main.sync {
				if let installationID = installationIDCache {
					return installationID
				} else if let keychainInstallationID = try! KeychainManager.getValue(for: KeychainKeys.installationID.rawValue) {
					installationIDCache = keychainInstallationID
					return keychainInstallationID
				} else {
					let generatedInstallationID = UUID().uuidString
					try! KeychainManager.setValue(generatedInstallationID, for: KeychainKeys.installationID.rawValue)
					installationIDCache = generatedInstallationID
					return generatedInstallationID
				}
			}
		}
	}
}
