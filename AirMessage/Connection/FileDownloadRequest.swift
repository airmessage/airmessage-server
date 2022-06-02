//
//  FileDownloadRequest.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-20.
//

import Foundation

struct FileDownloadRequestCreateError: LocalizedError {
	let path: String
	
	var errorDescription: String? {
		"Failed to create file at \(path)"
	}
}

class FileDownloadRequest {
	private static let timeout: TimeInterval = 10
	
	let requestID: Int16
	let fileName: String
	let customData: Any
	
	private(set) var packetsWritten = 0
	
	private var timeoutTimer: DispatchSourceTimer?
	var timeoutCallback: (() -> Void)?
	
	private let fileDirURL: URL //The container directory of the file
	let fileURL: URL //The file
	let fileHandle: FileHandle
	
	private let decompressPipe: CompressionPipeInflate
	
	private let timerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".download.timer", qos: .utility)
	
	/**
	 Initializes a new file download request
	 - Parameters:
	   - fileName: The name of the file to save
	   - requestID: A number to represent this request, not used internally
	   - customData: Any extra data to associate with this request, not used internally
	 */
	init(fileName: String, requestID: Int16, customData: Any) throws {
		self.fileName = fileName
		self.requestID = requestID
		self.customData = customData
		
		//Initialize the decompression pipe
		decompressPipe = try CompressionPipeInflate()
		
		//Find a place to store this file
		fileDirURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: fileDirURL, withIntermediateDirectories: false, attributes: nil)
		fileURL = fileDirURL.appendingPathComponent(fileName, isDirectory: false)
		guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
			throw FileDownloadRequestCreateError(path: fileURL.path)
		}
		
		//Open a file handle to the file
		do {
			fileHandle = try FileHandle(forWritingTo: fileURL)
		} catch {
			//Clean up and rethrow
			try? FileManager.default.removeItem(at: fileDirURL)
			throw error
		}
	}
	
	/**
	 Appends data to this request, decompressing it and writing it to the file
	 */
	func append(_ data: inout Data) throws {
		//Decompress the data
		let decompressedData = try decompressPipe.pipe(data: &data)
		
		//Write the data
		try fileHandle.writeCompat(contentsOf: decompressedData)
		
		//Update the counter
		packetsWritten += 1
	}
	
	/**
	 Gets if this download request has received all the data it needs, and should be completed
	 */
	var isDataComplete: Bool { decompressPipe.isFinished }
	
	/**
	 Starts or resets the timeout timer, which invokes `timeoutCallback`
	 */
	func startTimeoutTimer() {
		timerQueue.sync {
			//Cancel the old timer
			timeoutTimer?.cancel()
			
			//Create the new timer
			let timer = DispatchSource.makeTimerSource(queue: timerQueue)
			timer.schedule(deadline: .now() + FileDownloadRequest.timeout, repeating: .never)
			timer.setEventHandler(handler: onTimeout)
			timer.resume()
			timeoutTimer = timer
		}
	}
	
	/**
	 Cancels the current timeout timer
	 */
	func stopTimeoutTimer() {
		timerQueue.sync {
			timeoutTimer?.cancel()
			timeoutTimer = nil
		}
	}
	
	private func onTimeout() {
		timeoutTimer = nil
		timeoutCallback?()
	}
	
	func cleanUp() throws {
		//Close the file handle
		try? fileHandle.closeCompat()
		
		//Remove the directory
		try FileManager.default.removeItem(at: fileDirURL)
	}
	
	deinit {
		//Make sure the timer is cancelled
		stopTimeoutTimer()
	}
}
