//
//  AirPacker.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-14.
//

import Foundation

struct AirPacker {
	private(set) var data: Data
	private var currentIndex = 0
	
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
	
	mutating func pack(short value: Int16) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(int value: Int32) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(long value: Int64) {
		appendPrimitive(value.bigEndian)
	}
	
	mutating func pack(payload value: Data) {
		pack(int: Int32(value.count))
		data.append(value)
	}
	
	mutating func pack(optionalPayload value: Data?) {
		if let value = value {
			pack(bool: true)
			pack(payload: value)
		} else {
			pack(bool: false)
		}
	}
	
	mutating func pack(string value: String) {
		pack(payload: value.data(using: .utf8)!)
	}
	
	mutating func pack(optionalString value: String?) {
		if let value = value {
			pack(bool: true)
			pack(string: value)
		} else {
			pack(bool: false)
		}
	}
	
	mutating func pack(arrayHeader value: Int32) {
		pack(int: value)
	}
	
	mutating func pack(stringArray value: [String]) {
		pack(arrayHeader: Int32(value.count))
		for item in value {
			pack(string: item)
		}
	}
	
	mutating func pack(packableArray value: [Packable]) {
		pack(arrayHeader: Int32(value.count))
		for item in value {
			item.pack(to: &self)
		}
	}
	
	// MARK: - Read
	
	/**
	 Deserializes the data into the primitive at offset
	 */
	private func deserializePrimitive<T>(fromByteOffset offset: Int, as type: T.Type) -> T {
		return data.withUnsafeBytes { ptr in
			ptr.load(fromByteOffset: offset, as: type)
		}
	}
	
	mutating func unpackBool() throws -> Bool {
		guard currentIndex + MemoryLayout<Bool>.size - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let value = data[currentIndex]
		currentIndex += 1
		return value != 0
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
	
	mutating func unpackPayload() throws -> Data {
		let length = Int(try unpackInt())
		
		//Protect against large allocations
		guard length < CommConst.maxPacketAllocation else {
			throw PackingError.allocationError
		}
		
		guard currentIndex + length - 1 < data.count else {
			throw PackingError.rangeError
		}
		
		let payload = data[currentIndex..<currentIndex + length]
		currentIndex += length
		return payload
	}
	
	mutating func unpackOptionalPayload() throws -> Data? {
		if try unpackBool() {
			return try unpackPayload()
		} else {
			return nil
		}
	}
	
	mutating func unpackString() throws -> String {
		if let string = String(data: try unpackPayload(), encoding: .utf8) {
			return string
		} else {
			throw PackingError.encodingError
		}
	}
	
	mutating func unpackOptionalString() throws -> String? {
		if try unpackBool() {
			return try unpackString()
		} else {
			return nil
		}
	}
	
	mutating func unpackArrayHeader() throws -> Int32 {
		return try unpackInt()
	}
	
	mutating func unpackStringArray() throws -> [String] {
		let count = try unpackArrayHeader()
		return try (0..<count).map { _ in try unpackString() }
	}
}

enum PackingError: Error {
	case rangeError
	case encodingError
	case allocationError
}

protocol Packable {
	func pack(to packer: inout AirPacker)
}
