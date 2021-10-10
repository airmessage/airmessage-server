//
// Created by Cole Feuer on 2021-10-02.
//

import Foundation

class UpdateHelper: NSObject {
	public static let shared = UpdateHelper()
	
	private static let updateBaseURL = "https://airmessage.org"
	private static let stableUpdateURL = URL(string: updateBaseURL + "/update/server/3.json")!
	private static let betaUpdateURL = URL(string: updateBaseURL + "/update/server-beta/3.json")!
	
	private var pendingUpdate: UpdateStruct?
	
	func checkUpdates(onError: @escaping (UpdateError) -> Void, onUpdate: @escaping (UpdateStruct) -> Void) {
		//Download update data
		URLSession.shared.dataTask(with: PreferencesManager.shared.betaUpdates ? UpdateHelper.betaUpdateURL : UpdateHelper.stableUpdateURL) { [self] (data, response, error) in
			if let error = error {
				LogManager.shared.log("Failed to download updates: %{public}", type: .notice, error.localizedDescription)
				DispatchQueue.main.async { onError(.networkError(error: error)) }
				return
			}
			
			guard let data = data,
				  let updateData = try? JSONDecoder().decode(UpdateCheckResult.self, from: data) else {
				LogManager.shared.log("Failed to parse update data", type: .notice)
				DispatchQueue.main.async { onError(.parseError) }
				return
			}
			
			//Ignoring if the update is incompatible
			var versionSplit: [Int] = []
			for version in updateData.osRequirement.components(separatedBy: ".") {
				guard let versionInt = Int(version) else {
					LogManager.shared.log("Failed to parse version int %{public} in %{public}", type: .notice, version, updateData.osRequirement)
					DispatchQueue.main.async { onError(.parseError) }
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
				DispatchQueue.main.async { onError(.compatibilityError) }
				return
			}
			
			//Index update notes
			guard !updateData.notes.isEmpty else {
				LogManager.shared.log("Can't apply update, no update notes found", type: .notice)
				DispatchQueue.main.async { onError(.parseError) }
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
					downloadURL = resolveDownloadURL(forAppleSilicon: updateData)
				} else {
					downloadURL = resolveDownloadURL(forIntel: updateData)
				}
			#elseif arch(arm64)
				downloadURL = resolveDownloadURL(forAppleSilicon: updateData)
			#else
				downloadURL = nil
			#endif
			
			guard let downloadURL = downloadURL else {
				LogManager.shared.log("Can't apply update, no URL available for architecture", type: .notice)
				DispatchQueue.main.async { onError(.compatibilityError) }
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
}

private func resolveDownloadURL(forIntel updateData: UpdateCheckResult) -> URL? {
	if let urlIntelString = updateData.urlIntel, let urlIntel = URL(string: urlIntelString) {
		return urlIntel
	} else {
		return nil
	}
}

private func resolveDownloadURL(forAppleSilicon updateData: UpdateCheckResult) -> URL? {
	if let urlAppleSiliconString = updateData.urlAppleSilicon, let urlAppleSilicon = URL(string: urlAppleSiliconString) {
		return urlAppleSilicon
	} else {
		//Fall back to Intel
		return resolveDownloadURL(forIntel: updateData)
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

enum UpdateError: Error {
	case networkError(error: Error)
	case parseError
	case compatibilityError
}
