//
// Created by Cole Feuer on 2021-11-12.
//

import Foundation
import Zlib

private let minChunkSize = 1024

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
		LogManager.log("Failed to initialize zlib stream: error code \(initError)", level: .error)
		return nil
	}
	defer {
		deflateEnd(&stream)
	}
	
	//Deflate the data
	var dataOut = Data(count: dataIn.count)
	let deflateError = dataIn.withUnsafeMutableBytes { (ptrIn: UnsafeMutableRawBufferPointer) -> Int32 in
		dataOut.withUnsafeMutableBytes { (ptrOut: UnsafeMutableRawBufferPointer) in
			stream.next_in = ptrIn.baseAddress!.assumingMemoryBound(to: Bytef.self)
			stream.avail_in = uInt(ptrIn.count)
			
			stream.next_out = ptrOut.baseAddress!.assumingMemoryBound(to: Bytef.self)
			stream.avail_out = uInt(ptrOut.count)
			
			return deflate(&stream, Z_FINISH)
		}
	}
	
	//Check for errors
	guard deflateError == Z_STREAM_END else {
		LogManager.log("Failed to deflate zlib: error code \(deflateError)", level: .error)
		return nil
	}
	
	//Return the data
	return dataOut.dropLast(Int(stream.avail_out))
}

/**
 Pipes data through zlib deflate
 */
class CompressionPipeDeflate {
	private var stream: z_stream
	private let chunkSize: Int?
	
	/**
	 Creates a new zlib deflate pipe.
	 
	 Setting the chunk size to the chunk size of each block of input is recommended,
	 though it can be set to nil to automatically determine this value
	 */
	init(chunkSize: Int? = nil) throws {
		stream = z_stream()
		let initError = withUnsafeMutablePointer(to: &stream) { streamPtr in
			zlibInitializeDeflate(streamPtr)
		}
		guard initError == Z_OK else {
			throw CompressionError.zlibError(initError)
		}
		
		self.chunkSize = chunkSize
	}
	
	deinit {
		deflateEnd(&stream)
	}
	
	/**
	 Pipes data through zlib to produce compressed output
	 - Parameters:
	   - dataIn: The data to compress
	   - isLast: Whether this is the last data block
	 */
	func pipe(data dataIn: inout Data, isLast: Bool) throws -> Data {
		return try dataIn.withUnsafeMutableBytes { (ptrIn: UnsafeMutableRawBufferPointer) in
			//Set the input data
			stream.next_in = ptrIn.baseAddress!.assumingMemoryBound(to: Bytef.self)
			stream.avail_in = uInt(ptrIn.count)
			
			//Create the result data collector
			var dataReturn = Data()
			
			repeat {
				//Initialize the output data
				var dataOut: Data
				if let chunkSize = chunkSize {
					dataOut = Data(count: chunkSize)
				} else {
					dataOut = Data(count: max(ptrIn.count, minChunkSize))
				}
				
				//Run deflate
				let deflateResult = dataOut.withUnsafeMutableBytes { (ptrOut: UnsafeMutableRawBufferPointer) -> Int32 in
					stream.next_out = ptrOut.baseAddress!.assumingMemoryBound(to: Bytef.self)
					stream.avail_out = uInt(ptrOut.count)
					
					return deflate(&stream, isLast ? Z_FINISH : Z_NO_FLUSH)
				}
				
				//Check the return code
				guard deflateResult != Z_STREAM_ERROR else {
					throw CompressionError.zlibError(deflateResult)
				}
				
				//Append the compressed data
				dataReturn.append(dataOut.dropLast(Int(stream.avail_out)))
			} while stream.avail_out == 0
			
			return dataReturn
		}
	}
}

/**
 Pipes data through zlib inflate
 */
class CompressionPipeInflate {
	private var stream: z_stream
	private(set) var isFinished = false
	private let chunkSize: Int?
	
	/**
	 Creates a new zlib inflate pipe.
	 
	 Setting the chunk size to the chunk size of each block of input is recommended,
	 though it can be set to nil to automatically determine this value
	 */
	init(chunkSize: Int? = nil) throws {
		stream = z_stream()
		let initError = zlibInitializeInflate(&stream)
		guard initError == Z_OK else {
			throw CompressionError.zlibError(initError)
		}
		self.chunkSize = chunkSize
	}
	
	deinit {
		inflateEnd(&stream)
	}
	
	/**
	 Pipes data through zlib to produce decompressed output
	 - Parameters:
	   - dataIn: The data to compress
	 */
	func pipe(data dataIn: inout Data) throws -> Data {
		//If the stream is already finished, don't allow the input of any more data
		guard !isFinished else {
			throw CompressionError.streamFinished
		}
		
		return try dataIn.withUnsafeMutableBytes { (ptrIn: UnsafeMutableRawBufferPointer) in
			//Set the input data
			stream.next_in = ptrIn.baseAddress!.assumingMemoryBound(to: Bytef.self)
			stream.avail_in = uInt(ptrIn.count)
			
			//Create the result data collector
			var dataReturn = Data()
			
			repeat {
				//Initialize the output data
				var dataOut: Data
				if let chunkSize = chunkSize {
					dataOut = Data(count: chunkSize)
				} else {
					dataOut = Data(count: max(ptrIn.count, minChunkSize))
				}
				
				//Run inflate
				let inflateResult = dataOut.withUnsafeMutableBytes { (ptrOut: UnsafeMutableRawBufferPointer) -> Int32 in
					stream.next_out = ptrOut.baseAddress!.assumingMemoryBound(to: Bytef.self)
					stream.avail_out = uInt(ptrOut.count)
					
					return inflate(&stream, Z_NO_FLUSH)
				}
				
				//Check the return code
				guard ![Z_STREAM_ERROR, Z_NEED_DICT, Z_DATA_ERROR, Z_MEM_ERROR].contains(inflateResult) else {
					throw CompressionError.zlibError(inflateResult)
				}
				
				//Set the finished flag if we reached the end of the stream
				if inflateResult == Z_STREAM_END {
					isFinished = true
				}
				
				//Append the decompressed data
				dataReturn.append(dataOut.dropLast(Int(stream.avail_out)))
			} while stream.avail_out == 0
			
			return dataReturn
		}
	}
}

enum CompressionError: Error {
	case zlibError(Int32)
	case streamFinished
}
