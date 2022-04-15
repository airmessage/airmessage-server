//
//  ContentTypeHelperTests.swift
//  AirMessageTests
//
//  Created by Cole Feuer on 2022-04-15.
//

import XCTest
@testable import AirMessage

class ContentTypeHelperTests: XCTestCase {
	func testCompareDifferent() {
		XCTAssertFalse(compareMIMETypes("image/png", "video/mp4"))
		XCTAssertFalse(compareMIMETypes("image/png", "image/jpeg"))
	}
	
	func testCompareEqual() {
		XCTAssertTrue(compareMIMETypes("image/png", "image/png"))
		XCTAssertTrue(compareMIMETypes("image/*", "image/*"))
	}
	
	func testCompareWildcard() {
		XCTAssertTrue(compareMIMETypes("*/*", "*/*"))
		XCTAssertTrue(compareMIMETypes("*/*", "image/png"))
		XCTAssertTrue(compareMIMETypes("image/png", "*/*"))
		XCTAssertTrue(compareMIMETypes("*/*", "image/*"))
	}
	
	func testInvalid() {
		XCTAssertFalse(compareMIMETypes("imagepng", "imagepng"))
		XCTAssertFalse(compareMIMETypes("**", "**"))
		XCTAssertFalse(compareMIMETypes("image/png", "imagepng"))
	}
}
