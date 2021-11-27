//
//  FileHandleCompat.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

import Foundation

extension FileHandle {
	func readCompat(upToCount count: Int) throws -> Data {
		if #available(macOS 10.15.4, *) {
			return try read(upToCount: count) ?? Data()
		} else {
			//FileHandle.readData(ofLength:) raises an NSException if the read fails
			var data: Data? = nil
			try ObjC.catchException {
				data = readData(ofLength: count)
			}
			return data!
		}
	}
	
	func writeCompat(contentsOf data: Data) throws {
		if #available(macOS 10.15.4, *) {
			try write(contentsOf: data)
		} else {
			//FileHandle.write(_:) raises an NSException if the write fails
			try ObjC.catchException {
				write(data)
			}
		}
	}
	
	func readToEndCompat() throws -> Data {
		if #available(macOS 10.15.4, *) {
			return try readToEnd() ?? Data()
		} else {
			//FileHandle.readDataToEndOfFile() raises an NSException if the read fails
			var data: Data? = nil
			try ObjC.catchException {
				data = readDataToEndOfFile()
			}
			return data!
		}
	}
	
	func closeCompat() throws {
		if #available(macOS 10.15, *) {
			try close()
		} else {
			closeFile()
		}
	}
	
	func seekToEndCompat() throws {
		if #available(macOS 10.15.4, *) {
			try seekToEnd()
		} else {
			//FileHandle.seekToEndOfFile() raises an NSException if the write fails
			try ObjC.catchException {
				seekToEndOfFile()
			}
		}
	}
}
