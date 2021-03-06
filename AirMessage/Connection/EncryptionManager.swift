//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation
import CommonCrypto
import OpenSSL

private let blockSize = 128 / 8 //128 bits
private let saltLen = 8 //8 bytes
private let ivLen = 12 //12 bytes (instead of 16 because of GCM)
private let keyIterationCount: UInt32 = 10000
private let keyLength = 128 / 8 //128 bits
private let tagLength = 128 / 8 //128 bits

private var encryptionPassword: String {
	PreferencesManager.shared.password
}

/**
 Generates cryptographically secure random data
 - Parameter count: The length of the data to initialize
 - Returns: Randomly generated data
 - Throws: An error if random data failed to generate
 */
func generateSecureData(count: Int) throws -> Data {
	var data = Data(count: count)
	let secResult = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
		SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
	}
	guard secResult == errSecSuccess else {
		throw EncryptionError.randomError
	}
	return data
}

/**
 Derives a key from a password and a salt
 */
private func deriveKey(password: String, salt: Data) throws -> Data {
	//Derive the key from the password
	var derivedKeyData = Data(count: keyLength)
	let derivationStatus = derivedKeyData.withUnsafeMutableBytes { (derivedKeyBytes: UnsafeMutableRawBufferPointer) in
		salt.withUnsafeBytes { (saltBytes: UnsafeRawBufferPointer) in
			CCKeyDerivationPBKDF(
					CCPBKDFAlgorithm(kCCPBKDF2),
					password, password.data(using: .utf8)!.count,
					saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
					CCPseudoRandomAlgorithm(CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256)),
					keyIterationCount,
					derivedKeyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), keyLength)
		}
	}
	
	//Check for errors
	guard derivationStatus == kCCSuccess else {
		throw EncryptionError.derivationError
	}
	
	return derivedKeyData
}

private enum CipherOperation: Int32 {
	case encrypt = 1
	case decrypt = 0
}

/**
 Runs a cipher operation on the data
 - Parameters:
   - input: The data to process
   - operation: 1 for encryption, or 0 for decryption
 - Returns: The processed data
 - Throws: Encryption errors
 */
private func cipher(data input: Data, withKey key: Data, withIV iv: Data, withOperation operation: CipherOperation) throws -> Data {
	try key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) in
		try iv.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer) in
			//Initialize the encryption context
			let ctx = EVP_CIPHER_CTX_new()
			defer { EVP_CIPHER_CTX_free(ctx) }
			
			//Initialize the encryption session
			let resultInit = EVP_CipherInit_ex(ctx,
							  EVP_aes_128_gcm(),
							  nil,
							  keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
							  ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
							  operation.rawValue
			)
			guard resultInit == 1 else {
				LogManager.log("Cipher failed: init error", level: .error)
				throw EncryptionError.cryptoError
			}
			
			//Disable padding
			//EVP_CIPHER_CTX_set_padding(ctx, 0)
			
			let inputCipher: Data
			var inputTag: UnsafeMutableRawBufferPointer?
			defer { inputTag?.deallocate() }
			if operation == .encrypt {
				//Encrypt the entire input
				inputCipher = input
			} else {
				//Java and Web Crypto append the tag to the end of the output, so we have to extract it
				inputCipher = input.dropLast(tagLength)
				
				let tagPointer = UnsafeMutableRawBufferPointer.allocate(byteCount: tagLength, alignment: 1)
				input.copyBytes(to: tagPointer, from: input.index(input.endIndex, offsetBy: -tagLength)..<input.endIndex)
				inputTag = tagPointer
				
				//Set the tag
				let resultCtrl = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, Int32(tagLength), tagPointer.baseAddress!)
				guard resultCtrl == 1 else {
					LogManager.log("Cipher failed: ctrl set tag error", level: .error)
					throw EncryptionError.cryptoError
				}
			}
			
			//Cipher the data
			//For most ciphers and modes, the amount of data written can be anything from zero bytes to (inl + cipher_block_size - 1) bytes
			let outputCapacity = inputCipher.count + blockSize - 1
			var output = Data(count: outputCapacity)
			var outputLen: Int32 = 0
			
			let resultUpdate = inputCipher.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) in
				output.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) in
					EVP_CipherUpdate(ctx,
									 outputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
									 &outputLen,
									 inputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
									 Int32(inputCipher.count))
				}
			}
			guard resultUpdate == 1 else {
				LogManager.log("Cipher failed: update error", level: .error)
				throw EncryptionError.cryptoError
			}
			
			//Finish the cipher
			let finalOutputCapacity = blockSize
			var finalOutput = Data(count: finalOutputCapacity)
			var finalOutputLen: Int32 = 0
			
			let resultFinal = finalOutput.withUnsafeMutableBytes { (finalOutputBytes: UnsafeMutableRawBufferPointer) in
				EVP_CipherFinal_ex(ctx,
								finalOutputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
								&finalOutputLen)
			}
			guard resultFinal == 1 else {
				LogManager.log("Cipher failed: final error", level: .error)
				throw EncryptionError.cryptoError
			}
			
			//Join the output and final output
			let result = output.prefix(Int(outputLen)) + finalOutput.prefix(Int(finalOutputLen))
			if operation == .encrypt {
				//Java and Web Crypto append the tag to the end of the output, so we'll match that functionality
				var tag = Data(count: tagLength)
				let resultCtrl = tag.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Int32 in
					EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, Int32(tagLength), ptr.baseAddress!)
				}
				guard resultCtrl == 1 else {
					LogManager.log("Cipher failed: ctrl get tag error", level: .error)
					throw EncryptionError.cryptoError
				}
				
				return result + tag
			} else {
				//Return the joined output and final output
				return result
			}
		}
	}
}

/**
 Encrypts data for network transmission
 */
func networkEncrypt(data: Data) throws -> Data {
	//Generate random data
	let salt = try generateSecureData(count: saltLen)
	let iv = try generateSecureData(count: ivLen)
	
	//Get the key
	let key = try deriveKey(password: encryptionPassword, salt: salt)
	
	//Encrypt the data
	let encryptedData = try cipher(data: data, withKey: key, withIV: iv, withOperation: .encrypt)
	
	//Return data with the combined salt, IV, and encrypted data
	return salt + iv + encryptedData
}

/**
 Decrypts data from network transmission
 */
func networkDecrypt(data: Data) throws -> Data {
	//Make sure the input data is long enough
	guard data.count >= saltLen + ivLen else {
		throw EncryptionError.inputError
	}
	
	//Get the input data
	let salt = data.subdata(in: 0..<saltLen)
	let iv = data.subdata(in: saltLen..<saltLen+ivLen)
	let encryptedData = data.subdata(in: saltLen+ivLen..<data.count)
	
	//Get the key
	let key = try deriveKey(password: encryptionPassword, salt: salt)
	
	//Decrypt the data
	let decryptedData = try cipher(data: encryptedData, withKey: key, withIV: iv, withOperation: .decrypt)
	
	//Return the decrypted data
	return decryptedData
}

enum EncryptionError: Error {
	case randomError
	case derivationError
	case cryptoError
	case inputError
}
