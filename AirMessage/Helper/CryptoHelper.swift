//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation
import CommonCrypto

//https://stackoverflow.com/a/42935601
func md5HashFile(url: URL) -> Data? {
	let bufferSize = 1024 * 1024
	
	do {
		//Open file for reading
		let file = try FileHandle(forReadingFrom: url)
		
		//Create and initialize the MD5 context
		var context = CC_MD5_CTX()
		CC_MD5_Init(&context)
		
		var doBreak: Bool
		repeat {
			doBreak = try autoreleasepool {
				//Read data
				let data = try file.readCompat(upToCount: bufferSize)
				
				//Check if there's any data to process
				if data.count > 0 {
					//Update the MD5 context
					data.withUnsafeBytes {
						_ = CC_MD5_Update(&context, $0.baseAddress, numericCast(data.count))
					}
					
					//Continue
					return false
				} else {
					//End of file
					return true
				}
			}
		} while !doBreak
		
		//Compute the MD5 digest
		var digest = Data(count: Int(CC_MD5_DIGEST_LENGTH))
		digest.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
			_ = CC_MD5_Final(ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), &context)
		}
		
		return digest
	} catch {
		LogManager.shared.log("Failed to calculate MD5 hash: %{public}", type: .error, error.localizedDescription)
		return nil
	}
}
