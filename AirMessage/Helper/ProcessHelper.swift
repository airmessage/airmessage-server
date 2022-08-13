//
//  ProcessHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2022-08-13.
//

import Foundation
import Sentry

///Starts a process, waits for it to finish, and logs any errors the process encountered while running
func runProcessCatchError(_ process: Process) throws {
	//Capture the process' error pipe
	let errorPipe = Pipe()
	process.standardOutput = nil
	process.standardError = errorPipe
	
	//Start the process
	if #available(macOS 10.13, *) {
		try process.run()
	} else {
		process.launch()
	}
	
	//Wait for the process to exit
	process.waitUntilExit()
	
	//Check the output code
	guard process.terminationStatus == 0 else {
		let errorFileHandle = errorPipe.fileHandleForReading
		
		let errorMessage: String?
		if let data = try? errorFileHandle.readToEndCompat(), !data.isEmpty {
			errorMessage = String(data: data, encoding: .utf8)
		} else {
			errorMessage = nil
		}
		
		//Throw a process error
		throw ProcessError(exitCode: process.terminationStatus, message: errorMessage)
	}
}

struct ProcessError: Error {
	let exitCode: Int32
	let message: String?
	
	init(exitCode: Int32, message: String?) {
		self.exitCode = exitCode
		self.message = message
	}
	
	public var localizedDescription: String {
		if let message = message {
			return "Exit code \(exitCode): \(message)"
		} else {
			return "Exit code \(exitCode)"
		}
	}
}