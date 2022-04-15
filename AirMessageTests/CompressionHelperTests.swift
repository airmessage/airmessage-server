//
//  CompressionHelperTests.swift
//  AirMessageTests
//
//  Created by Cole Feuer on 2022-04-15.
//

import XCTest
@testable import AirMessage

class CompressionHelperTests: XCTestCase {
    func testCompressDecompress() throws {
		//Pseudorandom data
		var rng = Xorshift128Plus()
		var originalData = Data(repeating: 0, count: 1024 * 1024)
		for i in originalData.indices {
			originalData[i] = UInt8.random(in: UInt8.min...UInt8.max, using: &rng)
		}
		
		//Deflate and inflate the data
		let deflatePipe = try CompressionPipeDeflate()
		var compressedData = try deflatePipe.pipe(data: &originalData, isLast: true)
		
		let inflatePipe = try CompressionPipeInflate()
		let decompressedData = try inflatePipe.pipe(data: &compressedData)
		
		//Make sure the data is the same
		XCTAssertEqual(originalData, decompressedData, "Original data wasn't the same as decompressed data")
    }

}

struct Xorshift128Plus: RandomNumberGenerator {
	private var xS: UInt64
	private var yS: UInt64
	
	/// Two seeds, `x` and `y`, are required for the random number generator (default values are provided for both).
	init(xSeed: UInt64 = 0, ySeed:  UInt64 = UInt64.max) {
		xS = xSeed == 0 && ySeed == 0 ? UInt64.max : xSeed // Seed cannot be all zeros.
		yS = ySeed
	}
	
	mutating func next() -> UInt64 {
		var x = xS
		let y = yS
		xS = y
		x ^= x << 23 // a
		yS = x ^ y ^ (x >> 17) ^ (y >> 26) // b, c
		return yS &+ y
	}
}
