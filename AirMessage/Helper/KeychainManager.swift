//
//  KeychainManager.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-17.
//

import Foundation
import Security

private let keychainService = "AirMessage"

class KeychainManager {
	private init() {}
	
	private static let queryBase: [String: Any] = [
		String(kSecClass): kSecClassGenericPassword,
		String(kSecAttrService): keychainService
	]
	
	/**
	* Sets the password for the specified account from the app's keychain, or nil if unavailable
	*/
	public static func setValue(_ value: String, for userAccount: String, withLabel label: String? = nil) throws {
		guard let encodedPassword = value.data(using: .utf8) else {
			throw KeychainError.serializationError
		}
		
		var query = queryBase
		query[String(kSecAttrAccount)] = userAccount
		
		if let label = label {
			query[String(kSecAttrLabel)] = label
		}
		
		var status = SecItemCopyMatching(query as CFDictionary, nil)
		switch status {
			case errSecSuccess:
				var attributesToUpdate: [String: Any] = [:]
				attributesToUpdate[String(kSecValueData)] = encodedPassword
				
				status = SecItemUpdate(query as CFDictionary,
									   attributesToUpdate as CFDictionary)
				if status != errSecSuccess {
					throw KeychainError.from(status: status)
				}
			case errSecItemNotFound:
				query[String(kSecValueData)] = encodedPassword
				
				status = SecItemAdd(query as CFDictionary, nil)
				if status != errSecSuccess {
					throw KeychainError.from(status: status)
				}
			default:
				throw KeychainError.from(status: status)
		}
	}
	
	/**
	* Gets the password for the specified account from the app's keychain, or nil if unavailable
	*/
	public static func getValue(for userAccount: String) throws -> String? {
		var query = queryBase
		query[String(kSecAttrAccount)] = userAccount
		
		query[String(kSecMatchLimit)] = kSecMatchLimitOne
		query[String(kSecReturnAttributes)] = kCFBooleanTrue
		query[String(kSecReturnData)] = kCFBooleanTrue
		
		var queryResult: AnyObject?
		let status = withUnsafeMutablePointer(to: &queryResult) {
			SecItemCopyMatching(query as CFDictionary, $0)
		}
		
		switch status {
			case errSecSuccess:
				guard
					let queriedItem = queryResult as? [String: Any],
					let passwordData = queriedItem[String(kSecValueData)] as? Data,
					let password = String(data: passwordData, encoding: .utf8)
				else {
					throw KeychainError.deserializationError
				}
				return password
			case errSecItemNotFound:
				return nil
			default:
				throw KeychainError.from(status: status)
		}
	}
	
	/**
	* Removes the value for the specified account from the app's keychain
	*/
	public static func removeValue(for userAccount: String) throws {
		var query = queryBase
		query[String(kSecAttrAccount)] = userAccount
		
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw KeychainError.from(status: status)
		}
	}
	
	/**
	* Removes all values from the app's keychain
	*/
	public static func removeAllValues() throws {
		let status = SecItemDelete(queryBase as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw KeychainError.from(status: status)
		}
	}
}

public enum KeychainError: Error, LocalizedError {
	case serializationError
	case deserializationError
	case unhandledError(message: String)
	
	public var errorDescription: String? {
		switch self {
			case .serializationError:
				return "Data serialization error"
			case .deserializationError:
				return "Data deserialization error"
			case .unhandledError(let message):
				return message
		}
	}
	
	static func from(status: OSStatus) -> KeychainError {
		let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unhandled error"
		return KeychainError.unhandledError(message: message)
	}
}
