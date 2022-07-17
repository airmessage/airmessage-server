//
//  MessagesLauncher.swift
//  AirMessageKit
//
//  Created by Cole Feuer on 2022-07-11.
//

import Foundation

///Handles launching Messages with AirMessageKit's agent
public class MessagesLauncher {
	private var messagesProcess: Process?
	
	///Gets whether the Messages process is running
	public var isRunning: Bool {
		messagesProcess?.isRunning ?? false
	}
	
	///Launches a new Messages process
	public func launch(withSockFile sockFile: URL) throws {
		let bundle = Bundle(for: type(of: self))
		let dylibPath = bundle.resourcePath! + "/libAirMessageKitAgent.dylib"
		guard FileManager.default.fileExists(atPath: dylibPath) else {
			throw MessagesLauncherError.noDylib(path: dylibPath)
		}
		print("Launch process with \(dylibPath)")
		
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/System/Applications/Messages.app/Contents/MacOS/Messages")
		process.environment = [
			"DYLD_INSERT_LIBRARIES": dylibPath,
			"AIRMESSAGEKIT_SOCK_FILE": sockFile.path
		]
		try process.run()
		
		messagesProcess = process
	}
	
	///Stops the active Messages process
	public func terminate() {
		guard let process = messagesProcess else { return }
		
		process.interrupt()
		process.waitUntilExit()
		messagesProcess = nil
	}
}


public enum MessagesLauncherError: Error {
	case noDylib(path: String)
}
