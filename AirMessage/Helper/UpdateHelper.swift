//
// Created by Cole Feuer on 2021-10-02.
//

import Foundation
import AppKit

class UpdateHelper: NSObject {
	private static let updateBaseURL = "https://airmessage.org"
	private static let stableUpdateURL = URL(string: updateBaseURL + "/update/server/3.json")!
	private static let betaUpdateURL = URL(string: updateBaseURL + "/update/server-beta/3.json")!
	private static let updateCheckInterval: TimeInterval = 60 * 60 * 24
	
	private static var updateTimer: Timer?
	private static var pendingUpdate: UpdateStruct?
	private static var updatePromptWindow: NSWindow?
	
	/**
	 Queries the online server for available updates
	 - Parameters:
	   - onError: A callback to run if an error occurs
	   - onUpdate: A callback to run if an update is found. Called with the update data, or nil if the app is up-to-date.
	 */
	static func checkUpdates(onError: ((UpdateError) -> Void)?, onUpdate: @escaping (UpdateStruct?) -> Void) {
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
				DispatchQueue.main.async { onUpdate(nil) }
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
			
			//Setting the pending update
			let updateStruct = UpdateStruct(
					version: updateData.versionName,
					notes: updateNotes,
					downloadURL: downloadURL,
					downloadExternal: updateData.externalDownload
			)
			DispatchQueue.main.async {
				pendingUpdate = updateStruct
				onUpdate(updateStruct)
			}
		}.resume()
	}
	
	/**
	 Starts background checking of updates
	 */
	static func startUpdateTimer() {
		guard updateTimer == nil else { return }
		
		let timer = Timer.scheduledTimer(timeInterval: UpdateHelper.updateCheckInterval, target: self, selector: #selector(updateTimerCheck), userInfo: nil, repeats: true)
		timer.fire() //Check for updates immediately
		updateTimer = timer
	}
	
	/**
	 Stops background checking of updates
	 */
	static func stopUpdateTimer() {
		updateTimer?.invalidate()
		updateTimer = nil
	}
	
	@objc private static func updateTimerCheck() {
		//Check for updates, show window
		checkUpdates(onError: nil, onUpdate: { _ in showUpdateWindow() })
	}
	
	/**
	 Shows a window that prompts the user to install an update
	 */
	static func showUpdateWindow() {
		if let window = updatePromptWindow {
			//Focus the window
			NSApp.activate(ignoringOtherApps: true)
			window.makeKey()
			
			//Don't create a new window
			return
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
				return String(format: NSLocalizedString("message.update.error.oscompat", comment: ""), minVersion.majorVersion, minVersion.minorVersion, minVersion.patchVersion)
			case .archCompatibilityError:
				return String(format: NSLocalizedString("message.update.error.archcompat", comment: ""), getSystemArchitecture())
		}
	}
}