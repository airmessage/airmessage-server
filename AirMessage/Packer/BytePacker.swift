//
//  BytePacker.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-25.
//

import Foundation

/**
 A structure for packing and unpacking raw data, similar to ByteBuffer
 */
struct BytePacker {
	private(set) var data: Data
	private(set) var currentIndex = 0
	public var count: Int { data.count }
	public var remaining: Int { data.count - currentIndex }
	
	// MARK: - Initialize
	
	init() {
		data = Data()
	}
	
	init(capacity: Int) {
		data = Data(capacity: capacity)
	}
	
	init(from source: Data) {
		data = source
	}
	
	mutating func reset() {
		data = Data()
	}
	
	mutating func reset(capacity: Int) {
		data = Data(capacity: capacity)
	}
	
	// MARK: - Write
	
	private mutating func appendPrimitive<T>(_ value: T) {
		withUnsafeBytes(of: value) { ptr in
			data.append(contentsOf: ptr)
		}
	}

	mutating func pack(bool value: Bool) {
		data.append(value ? 1 : 0)
	}
	
	mutating func pack(byte value: Int8) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(short value: Int16) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(int value: Int32) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(long value: Int64) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(data value: Data) {
		data.append(value)
	}
	
	// MARK: - Read
	
	/**
	 Deserializes the data into the primitive at offset
	 */
	private func deserializePrimitive<T>(fromByteOffset offset: Int, as type: T.Type) -> T {
		return data.subdata(in: offset..<offset + MemoryLayout<T>.size)
			.withUnsafeBytes { $0.load(as: type) }
	}
	
	mutating func unpackBool() throws -> Bool {
		guard currentIndex + MemoryLayout<Bool>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = data[currentIndex]
		currentIndex += 1
		return value != 0
	}
	
	mutating func unpackByte() throws -> Int8 {
		guard currentIndex + MemoryLayout<Int8>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = deserializePrimitive(fromByteOffset: currentIndex, as: Int8.self)
		currentIndex += MemoryLayout<Int8>.size
		return Int8(bigEndian: value)
	}
	
	mutating func unpackShort() throws -> Int16 {
		guard currentIndex + MemoryLayout<Int16>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = deserializePrimitive(fromByteOffset: currentIndex, as: Int16.self)
		currentIndex += MemoryLayout<Int16>.size
		return Int16(bigEndian: value)
	}
	
	mutating func unpackInt() throws -> Int32 {
		guard currentIndex + MemoryLayout<Int32>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = deserializePrimitive(fromByteOffset: currentIndex, as: Int32.self)
		currentIndex += MemoryLayout<Int32>.size
		return Int32(bigEndian: value)
	}
	
	mutating func unpackLong() throws -> Int64 {
		guard currentIndex + MemoryLayout<Int64>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = deserializePrimitive(fromByteOffset: currentIndex, as: Int64.self)
		currentIndex += MemoryLayout<Int64>.size
		return Int64(bigEndian: value)
	}
	
	mutating func unpackData(length: Int? = nil) throws -> Data {
		if let length = length {
			//Unpack data of length
			guard currentIndex + length - 1 < data.count else {
				throw PackingError.rangeError
			}
			
			let payload = data.subdata(in: currentIndex..<currentIndex + length)
			currentIndex += length
			return payload
		} else {
			//Unpack until the end
			guard currentIndex < data.count else {
				throw PackingError.rangeError
			}
			
			let payload = data.subdata(in: currentIndex..<data.count)
			currentIndex = data.count
			return payload
		}
	}
	
	/**
	 Moves the current index backwards for the memory size of type
	 */
	mutating func backtrack<T>(size type: T.Type) {
		currentIndex -= MemoryLayout<T>.size
	}
}
