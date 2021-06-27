import Foundation
import Compression

private let encodeAlgorithm = COMPRESSION_ZLIB

/* func compressBuffer(_ buffer: [UInt8], size: Int) throws -> [UInt8] {
	let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
	defer {
		destinationBuffer.deallocate()
	}
	let compressedSize = compression_encode_buffer(destinationBuffer, size,
			buffer, size,
			nil,
			encodeAlgorithm)
	guard compressedSize > 0 else {
		throw NSError(domain: "Failed to compress", code: 0)
	}
	
	return Array(UnsafeBufferPointer(start: destinationBuffer, count: compressedSize))
} */
