//
//  FileNormalizationHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-15.
//

import Foundation
import Sentry

struct NormalizedFile {
	let url: URL
	let type: String
	let name: String
}

/**
 Converts a file from Apple-specific formats to formats that are readable by non-Apple devices.
 The resulting file is stored in a temporary location, and should be cleaned up after it is finished being used.
 This function does not modify or remove the input file.
 - Parameters:
   - inputFile: The file to process
   - extension: The extension type of the file
 - Returns: A tuple with the updated file path and string, or NIL if the file was not converted
 */
func normalizeFile(url inputFile: URL, ext: String) -> NormalizedFile? {
	/*
	 These conversions are only available on macOS 10.13+,
	 but older versions have these files converted before they
	 even reach the device anyways
	 */
	guard #available(macOS 10.13, *) else { return nil }
	
	if ext.caseInsensitiveCompare("heic") == .orderedSame {
		LogManager.log("Converting file \(inputFile.lastPathComponent) from HEIC", level: .info)
		
		//Get a temporary file
		let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString + ".jpeg")
		
		//Convert the file with sips
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
		process.arguments = ["--setProperty", "format", "jpeg", inputFile.path, "--out", tempFile.path]
		do {
			try runProcessCatchError(process)
		} catch {
			LogManager.log("Failed to convert file \(inputFile.path) from HEIC to JPEG: \(error)", level: .info)
			try? FileManager.default.removeItem(at: tempFile) //Clean up immediately
			return nil
		}
		
		//Build the new file name
		let newFileName = inputFile.deletingPathExtension().lastPathComponent + ".jpeg"
		
		return NormalizedFile(url: tempFile, type: "image/jpeg", name: newFileName)
	} else if ext.caseInsensitiveCompare("caf") == .orderedSame {
		LogManager.log("Converting file \(inputFile.lastPathComponent) from CAF", level: .info)
		
		//Get a temporary file
		let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString + ".mp4")
		
		//Convert the file with sips
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
		process.arguments = ["-f", "mp4f", "-d", "aac", inputFile.path, "-o", tempFile.path]
		do {
			try runProcessCatchError(process)
		} catch {
			LogManager.log("Failed to convert file \(inputFile.path) from CAF to MP4: \(error)", level: .info)
			try? FileManager.default.removeItem(at: tempFile) //Clean up immediately
			return nil
		}
		
		//Build the new file name
		let newFileName = inputFile.deletingPathExtension().lastPathComponent + ".mp4"
		
		return NormalizedFile(url: tempFile, type: "audio/mp4", name: newFileName)
	} else {
		return nil
	}
}
