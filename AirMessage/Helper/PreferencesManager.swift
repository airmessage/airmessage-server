//
// Created by Cole Feuer on 2021-06-27.
//

import Foundation

let defaultServerPort = 1359

class PreferencesManager {
	public static let shared = PreferencesManager()
	
	private init() {}
	
	// MARK: UserDefaults
	
	private enum UDKeys: String, CaseIterable {
		//Settings
		case serverPort
		case checkUpdates
		case betaUpdates
		case accountType
		
		//Storage
		case idToken
		case idTokenExpiry
	}
	
	var serverPort: Int {
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
	
	var accountType: AccountType {
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
	
	var idToken: String? {
		get {
			UserDefaults.standard.string(forKey: UDKeys.idToken.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.idToken.rawValue)
		}
	}
	
	var idTokenExpiry: Int {
		get {
			UserDefaults.standard.integer(forKey: UDKeys.idTokenExpiry.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.idTokenExpiry.rawValue)
		}
	}
	
	// MARK: Keychain
	
	private enum KeychainAccount: String, CaseIterable {
		case password = "airmessage-password"
		case refreshToken = "refresh-token"
		case installationID = "airmessage-installation"
	}
	
	private var cacheMap = [String: String]()
	
	private func getValue(for account: KeychainAccount) -> String? {
		runOnMain {
			if let cacheValue = cacheMap[account.rawValue] {
				return cacheValue
			} else {
				let keychainValue = try! KeychainManager.getValue(for: account.rawValue)
				cacheMap[account.rawValue] = keychainValue
				return keychainValue
			}
		}
	}
	
	private func setValue(_ value: String, for account: KeychainAccount) {
		runOnMainAsync {
			try! KeychainManager.setValue(value, for: account.rawValue)
			self.cacheMap[account.rawValue] = value
		}
	}
	
	var password: String {
		get {
			self.getValue(for: KeychainAccount.password) ?? ""
		}
		set(newValue) {
			setValue(newValue, for: KeychainAccount.password)
		}
	}
	
	var refreshToken: String {
		get {
			self.getValue(for: KeychainAccount.refreshToken) ?? ""
		}
		set(newValue) {
			setValue(newValue, for: KeychainAccount.refreshToken)
		}
	}
	
	var installationID: String {
		get {
			runOnMain {
				if let installationID = getValue(for: KeychainAccount.installationID) {
					return installationID
				} else {
					let generatedInstallationID = UUID().uuidString
					setValue(generatedInstallationID, for: KeychainAccount.installationID)
					return generatedInstallationID
				}
			}
		}
	}
}
