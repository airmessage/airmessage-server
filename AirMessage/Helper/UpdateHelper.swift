//
// Created by Cole Feuer on 2021-10-02.
//

import Foundation
import AppKit
import Zip

class UpdateHelper: NSObject {
	//Constants
	private static let updateBaseURL = "http://localhost:4000"
	private static let stableUpdateURL = URL(string: updateBaseURL + "/update/server/3.json")!
	private static let betaUpdateURL = URL(string: updateBaseURL + "/update/server-beta/3.json")!
	private static let updateCheckInterval: TimeInterval = 60 * 60 * 24
	
	//Pending and installing update state
	@objc private(set) static var pendingUpdate: UpdateStruct?
	private static var isInstallingUpdate = false
	
	//Timer for periodic update checks
	private static var updateTimer: Timer?
	
	//The currently displayed update prompt window
	private static var updatePromptWindow: NSWindow?
	
	//Incremented update ID value
	private static var nextUpdateID = 0
	
	/**
	 Queries the online server for available updates
	 - Parameters:
	   - onError: A callback to run if an error occurs
	   - onUpdate: A callback to run if an update is found.
	    		   Called with the update data, or nil if the app is up-to-date,
	    		   and a boolean that represents whether this update is new information.
	 */
	public static func checkUpdates(onError: ((UpdateError) -> Void)?, onUpdate: @escaping (UpdateStruct?, Bool) -> Void) {
		//Download update data
		URLSession.shared.dataTask(with: PreferencesManager.shared.betaUpdates ? UpdateHelper.betaUpdateURL : UpdateHelper.stableUpdateURL) { [self] (data, response, error) in
			func notifyError(_ error: UpdateError) {
				if let onError = onError {
					DispatchQueue.main.async { onError(.networkError(error: error)) }
				}
			}
			
			if let error = error {
				LogManager.shared.log("Failed to download updates: %{public}", type: .notice, error.localizedDescription)
				notifyError(.networkError(error: error))
				return
			}
			
			guard let data = data,
				  let updateData = try? JSONDecoder().decode(UpdateCheckResult.self, from: data) else {
				LogManager.shared.log("Failed to parse update data", type: .notice)
				notifyError(.parseError)
				return
			}
			
			//Checking if the update is newer
			guard updateData.versionCode > Int(Bundle.main.infoDictionary!["CFBundleVersion"] as! String)! else {
				LogManager.shared.log("No newer update available", type: .info)
				DispatchQueue.main.async {
					let updateNew = pendingUpdate != nil
					pendingUpdate = nil
					onUpdate(nil, updateNew)
				}
				return
			}
			
			//Ignoring if the update is incompatible
			var versionSplit: [Int] = []
			for version in updateData.osRequirement.components(separatedBy: ".") {
				guard let versionInt = Int(version) else {
					LogManager.shared.log("Failed to parse version int %{public} in %{public}", type: .notice, version, updateData.osRequirement)
					notifyError(.parseError)
					return
				}
				versionSplit.append(versionInt)
			}
			
			var minimumVersion = OperatingSystemVersion()
			switch versionSplit.count {
				case 3..<Int.max:
					minimumVersion.patchVersion = versionSplit[2]
					fallthrough
				case 2:
					minimumVersion.minorVersion = versionSplit[1]
					fallthrough
				case 1:
					minimumVersion.majorVersion = versionSplit[0]
					fallthrough
				default:
					break
			}
			
			guard ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumVersion) else {
				LogManager.shared.log("Can't apply update, required OS version is %{public}.%{public}.%{public}", type: .info, minimumVersion.majorVersion, minimumVersion.minorVersion, minimumVersion.patchVersion)
				notifyError(.osCompatibilityError(minVersion: minimumVersion))
				return
			}
			
			//Index update notes
			guard !updateData.notes.isEmpty else {
				LogManager.shared.log("Can't apply update, no update notes found", type: .notice)
				notifyError(.parseError)
				return
			}
			
			let updateNotesDict = updateData.notes.reduce(into: [String: String]()) { (array, notes) in
				array[notes.lang] = notes.message
			}
			
			//Find a matching locale
			let updateNotes: String
			if let languageCode = Locale.autoupdatingCurrent.languageCode,
			   let languageNotes = updateNotesDict[languageCode] {
				updateNotes = languageNotes
			} else {
				//Default to the first locale
				updateNotes = updateData.notes[0].message
			}
			
			//Find a matching download URL
			let downloadURL: URL?
			#if arch(x86_64)
				if isProcessTranslated() {
					//Try for Apple Silicon
					downloadURL = UpdateHelper.resolveDownloadURL(forAppleSilicon: updateData)
				} else {
					downloadURL = UpdateHelper.resolveDownloadURL(forIntel: updateData)
				}
			#elseif arch(arm64)
				downloadURL = UpdateHelper.resolveDownloadURL(forAppleSilicon: updateData)
			#else
				downloadURL = nil
			#endif
			
			guard let downloadURL = downloadURL else {
				LogManager.shared.log("Can't apply update, no URL available for architecture", type: .notice)
				notifyError(.archCompatibilityError)
				return
			}
			
			DispatchQueue.main.async {
				//Checking if this update is the same as the pending update
				if let pendingUpdate = pendingUpdate,
				   pendingUpdate.versionCode == updateData.versionCode,
				   pendingUpdate.versionName == updateData.versionName,
				   pendingUpdate.downloadURL == downloadURL,
				   pendingUpdate.downloadExternal == updateData.externalDownload {
					onUpdate(pendingUpdate, false)
				} else {
					//Setting the pending update
					let updateStruct = UpdateStruct(
							id: nextUpdateID,
							versionCode: updateData.versionCode,
							versionName: updateData.versionName,
							notes: updateNotes,
							downloadURL: downloadURL,
							downloadExternal: updateData.externalDownload
					)
					nextUpdateID += 1
					
					pendingUpdate = updateStruct
					onUpdate(updateStruct, true)
				}
			}
		}.resume()
	}
	
	/**
	 Starts background checking of updates
	 */
	public static func startUpdateTimer() {
		guard updateTimer == nil else { return }
		
		let timer = Timer.scheduledTimer(timeInterval: UpdateHelper.updateCheckInterval, target: self, selector: #selector(updateTimerCheck), userInfo: nil, repeats: true)
		timer.fire() //Check for updates immediately
		updateTimer = timer
	}
	
	/**
	 Stops background checking of updates
	 */
	public static func stopUpdateTimer() {
		updateTimer?.invalidate()
		updateTimer = nil
	}
	
	@objc private static func updateTimerCheck() {
		//Check for updates, show window
		checkUpdates(onError: nil, onUpdate: { update, isNew in
			showUpdateWindow(for: update, isNew: isNew, backgroundMode: true)
		})
	}
	
	/**
	 Handles the display of a window that prompts the user to update.
	 If no update is available, the window is closed.
	 
	 - Parameters:
	   - update: The update to display, or nil if there is no update
	   - isNew: If the update changed from the previous time this window was shown
	   - backgroundMode: Whether to pass up focus to this window
	 */
	public static func showUpdateWindow(for update: UpdateStruct?, isNew: Bool, backgroundMode: Bool) {
		if let window = updatePromptWindow {
			//If this is a new update or no update is available, close the window
			if isNew || update == nil {
				window.close()
				updatePromptWindow = nil
			}
			//If this is not a new update, re-focus the window
			else if update != nil {
				if !backgroundMode {
					//Focus the window
					NSApp.activate(ignoringOtherApps: true)
					window.makeKey()
				}
				
				//Don't create a new window
				return
			}
		}
		
		//Get update data
		guard let updateData = pendingUpdate else { return }
		
		//Show window
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "SoftwareUpdate") as! NSWindowController
		let viewController = windowController.window!.contentViewController as! SoftwareUpdateViewController
		viewController.updateData = updateData
		windowController.showWindow(nil)
		
		//Save the window reference for later
		updatePromptWindow = windowController.window!
		
		//Register for updates when the window closes
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateWindowClose), name: NSWindow.willCloseNotification, object: nil)
	}
	
	@objc private static func onUpdateWindowClose() {
		//Clean up references
		updatePromptWindow = nil
		
		//Unregister the observer
		NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
	}
	
	/**
	 Downloads and installs an update in the background
	 - Parameters:
	   - update: The update to install
	   - onProgress: A periodically invoked progress callback, with a double between 0 and 100
	   - onSuccess: A callback called on success
	   - onError: A callback called when an error occurs, with an error code and description
	 - Returns: Whether the update was scheduled to be installed. If this function returns false, no callbacks will be invoked.
	 */
	public static func install(update: UpdateStruct, onProgress: ((Double) -> ())?, onSuccess: (() -> ())?, onError: ((UpdateErrorCode, String) -> ())?) -> Bool {
		LogManager.shared.log("Installing update...", type: .info)
		
		//Ignore if we're already installing an update
		guard !isInstallingUpdate else { return false }
		
		isInstallingUpdate = true
		
		var urlSession: URLSession!
		func cleanup() {
			//Reset the update state
			DispatchQueue.main.async { isInstallingUpdate = false }
			
			//Invalidate the session
			urlSession.finishTasksAndInvalidate()
		}
		
		//Intercept onSuccess and onError to perform cleanup
		let onSuccessIntercept = {
			onSuccess?()
			cleanup()
		}
		let onErrorIntercept = { (code: UpdateErrorCode, message: String) in
			onError?(code, message)
			cleanup()
		}
		
		//Download the update file
		urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: UpdateDownloadURLDelegate(onProgress: onProgress, onSuccess: onSuccessIntercept, onError: onErrorIntercept), delegateQueue: nil)
		let task = urlSession.downloadTask(with: update.downloadURL)
		task.resume()
		
		return true
	}
	
	/**
	 Gets the download URL from an update check result for Intel devices
	 */
	private static func resolveDownloadURL(forIntel updateData: UpdateCheckResult) -> URL? {
		if let urlIntelString = updateData.urlIntel, let urlIntel = URL(string: urlIntelString) {
			return urlIntel
		} else {
			return nil
		}
	}
	
	/**
	 Gets the download URL from an update check result for Apple Silicon devices
	 */
	private static func resolveDownloadURL(forAppleSilicon updateData: UpdateCheckResult) -> URL? {
		if let urlAppleSiliconString = updateData.urlAppleSilicon, let urlAppleSilicon = URL(string: urlAppleSiliconString) {
			return urlAppleSilicon
		} else {
			//Fall back to Intel
			return UpdateHelper.resolveDownloadURL(forIntel: updateData)
		}
	}
}

private struct UpdateCheckResult: Decodable {
	let versionCode: Int
	let versionName: String
	let osRequirement: String
	let notes: [UpdateNotes]
	let urlIntel: String?
	let urlAppleSilicon: String?
	let externalDownload: Bool
}

private struct UpdateNotes: Decodable {
	let lang: String
	let message: String
}

private class UpdateDownloadURLDelegate: NSObject, URLSessionDownloadDelegate {
	private let onProgress: ((Double) -> Void)?
	private let onSuccess: (() -> Void)?
	private let onError: ((UpdateErrorCode, String) -> Void)?
	
	init(onProgress: ((Double) -> ())?, onSuccess: (() -> ())?, onError: ((UpdateErrorCode, String) -> ())?) {
		self.onProgress = onProgress
		self.onSuccess = onSuccess
		self.onError = onError
		super.init()
	}
	
	private func notifyProgress(_ progress: Double) {
		if let onProgress = onProgress {
			DispatchQueue.main.async { onProgress(progress) }
		}
	}
	
	private func notifySuccess() {
		if let onSuccess = onSuccess {
			DispatchQueue.main.async { onSuccess() }
		}
	}
	
	private func notifyError(code: UpdateErrorCode, message: String) {
		if let onError = onError {
			DispatchQueue.main.async { onError(code, message) }
		}
	}
	
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		if let error = downloadTask.error {
			LogManager.shared.log("Can't apply update, download error: %{public}", type: .notice, error.localizedDescription)
			notifyError(code: UpdateErrorCode.download, message: error.localizedDescription)
			return
		}
		
		guard let httpResponse = downloadTask.response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
			LogManager.shared.log("Can't apply update, HTTP response error", type: .notice)
			notifyError(code: UpdateErrorCode.download, message: "HTTP response error")
			return
		}
		
		do {
			//Get Applications directory
			let destinationFolder = try FileManager.default.url(for: .applicationDirectory, in: .localDomainMask, appropriateFor: nil, create: false)
			
			//Get the temporary directory
			let temporaryDirectory = try FileManager.default.url(
					for: .itemReplacementDirectory,
					in: .userDomainMask,
					appropriateFor: destinationFolder,
					create: true
			)
			
			//Get the download targets
			let zippedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip", isDirectory: false)
			let unzippedFolder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
			
			//Move the downloaded file to a temporary location, and append the .zip extension
			try FileManager.default.moveItem(at: location, to: zippedFile)
			LogManager.shared.log("Downloaded and moved update file to %@", type: .info, zippedFile.path)
			
			//Unzip file
			try Zip.unzipFile(zippedFile, destination: unzippedFolder, overwrite: true, password: nil)
			LogManager.shared.log("Decompressed update file to %@", type: .info, unzippedFolder.path)
			
			//Find app file
			guard let updateAppFile = try FileManager.default.contentsOfDirectory(at: unzippedFolder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "app" }).first else {
				LogManager.shared.log("Can't apply update, can't find app file in update archive", type: .notice)
				notifyError(code: UpdateErrorCode.badPackage, message: "Can't find app file in update archive")
				return
			}
			
			//Get target file in Applications
			let targetAppFile = destinationFolder.appendingPathComponent(updateAppFile.lastPathComponent, isDirectory: false)
			LogManager.shared.log("Targeting update location %@", type: .info, targetAppFile.path)
			
			//Delete old zip file
			try FileManager.default.removeItem(at: zippedFile)
			
			//Load the update script
			let updateScript = try! String(contentsOf: Bundle.main.url(forResource: "SoftwareUpdate", withExtension: "sh")!)
			
			//Start the update process
			let process = Process()
			process.arguments = ["-c", updateScript, String(ProcessInfo.processInfo.processIdentifier), updateAppFile.path, targetAppFile.path]
			if #available(macOS 10.13, *) {
				process.executableURL = URL(fileURLWithPath: "/bin/sh")
				try process.run()
			} else {
				process.launchPath = "/bin/sh"
				process.launch()
			}
			
			LogManager.shared.log("Started update process", type: .info)
			
			DispatchQueue.main.async { [self] in
				//Call the success callback
				onSuccess?()
				
				//Quit the app
				NSApplication.shared.terminate(self)
			}
		} catch {
			//Log the error
			LogManager.shared.log("Failed to download update: %s", type: .notice, error.localizedDescription)
			
			//Show an error
			notifyError(code: UpdateErrorCode.internalError, message: error.localizedDescription)
		}
	}
	
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		notifyProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
	}
}

enum UpdateError: Error, LocalizedError {
	case networkError(error: Error)
	case parseError
	case osCompatibilityError(minVersion: OperatingSystemVersion)
	case archCompatibilityError
	
	var errorDescription: String? {
		switch self {
			case .networkError(let error):
				return error.localizedDescription
			case .parseError:
				return NSLocalizedString("message.update.error.parse", comment: "")
			case .osCompatibilityError(let minVersion):
				return String(format: NSLocalizedString("message.update.error.os_compat", comment: ""), minVersion.majorVersion, minVersion.minorVersion, minVersion.patchVersion)
			case .archCompatibilityError:
				return String(format: NSLocalizedString("message.update.error.arch_compat", comment: ""), getSystemArchitecture())
		}
	}
}
