//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation

/**
 Compresses the data with zlib
 - Parameter dataIn: The data to compress
 - Returns: The compressed data, or nil if an error occurred
 */
func compressData(_ dataIn: inout Data) -> Data? {
	//Initialize zlib stream
	var stream = z_stream()
	let initError = zlibInitializeDeflate(&stream)
	guard initError == Z_OK else {
		LogManager.shared.log("Failed to initialize zlib stream: error code %{public}", type: .error, initError)
		return nil
	}
	
	//Deflate the data
	var dataOut = Data(capacity: dataIn.count)
	let deflateError = dataIn.withUnsafeMutableBytes { (ptrIn: UnsafeMutableRawBufferPointer) -> Int32 in
		dataOut.withUnsafeMutableBytes { (ptrOut: UnsafeMutableRawBufferPointer) -> Int32 in
			stream.next_in = ptrIn.baseAddress!.bindMemory(to: Bytef.self, capacity: ptrIn.count)
			stream.avail_in = uInt(ptrIn.count)
			
			stream.next_out = ptrOut.baseAddress!.bindMemory(to: Bytef.self, capacity: ptrOut.count)
			stream.avail_out = uInt(ptrOut.count)
			
			return deflate(&stream, Z_FINISH)
		}
	}
	
	//Check for errors
	guard deflateError == Z_STREAM_END else {
		LogManager.shared.log("Failed to deflate zlib: error code %{public}", type: .error, deflateError)
		deflateEnd(&stream)
		return nil
	}
	
	//Return the data
	return dataOut.dropLast(Int(stream.avail_out))
}
