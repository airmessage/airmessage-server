//
// Created by Cole Feuer on 2021-06-27.
//

import Foundation
import Sentry

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
		case faceTimeIntegration
		case accountType
		
		//Storage
		case connectUserID
		case connectEmailAddress
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
	
	var faceTimeIntegration: Bool {
		get {
			UserDefaults.standard.bool(forKey: UDKeys.faceTimeIntegration.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.faceTimeIntegration.rawValue)
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
	
	var connectUserID: String? {
		get {
			UserDefaults.standard.string(forKey: UDKeys.connectUserID.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.connectUserID.rawValue)
		}
	}
	
	var connectEmailAddress: String? {
		get {
			UserDefaults.standard.string(forKey: UDKeys.connectEmailAddress.rawValue)
		}
		set(newValue) {
			UserDefaults.standard.set(newValue, forKey: UDKeys.connectEmailAddress.rawValue)
		}
	}
	
	// MARK: Keychain
	
	private enum KeychainAccount: String, CaseIterable {
		case password = "airmessage-password"
		case installationID = "airmessage-installation"
	}
	
	private var keychainInitialized = false
	private var keychainValues = [String: String]()
	
	func initializeKeychain() throws {
		try runOnMain {
			guard !keychainInitialized else { return }
			
			do {
				//Load all Keychain accounts into the cache map
				for account in KeychainAccount.allCases {
					keychainValues[account.rawValue] = try KeychainManager.getValue(for: account.rawValue)
				}
				
				//Generate an installation ID if one isn't present
				if keychainValues[KeychainAccount.installationID.rawValue] == nil {
					let generatedInstallationID = UUID().uuidString
					try setValue(generatedInstallationID, for: KeychainAccount.installationID)
				}
				
				keychainInitialized = true
			} catch {
				LogManager.log("Failed to load Keychain values: \(error.localizedDescription)", level: .notice)
				SentrySDK.capture(error: error)
				
				//Rethrow error
				throw error
			}
		}
	}
	
	private func setValue(_ value: String, for account: KeychainAccount) throws {
		try runOnMain {
			try KeychainManager.setValue(value, for: account.rawValue)
			keychainValues[account.rawValue] = value
		}
	}
	
	var password: String {
		keychainValues[KeychainAccount.password.rawValue] ?? ""
	}
	
	func setPassword(_ password: String) throws {
		try setValue(password, for: KeychainAccount.password)
	}
	
	var installationID: String {
		keychainValues[KeychainAccount.installationID.rawValue]!
	}
}
