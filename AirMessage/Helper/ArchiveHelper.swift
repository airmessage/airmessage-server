//
//  ArchiveHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2022-08-13.
//

import Foundation

func decompressArchive(fromURL: URL, to toURL: URL) throws {
	//Run ditto to extract the files
	let process = Process()
	if #available(macOS 10.13, *) {
		process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
	} else {
		process.launchPath = "/usr/bin/ditto"
	}
	process.arguments = ["-x", "-k", fromURL.path, toURL.path]
	try runProcessCatchError(process)
}
