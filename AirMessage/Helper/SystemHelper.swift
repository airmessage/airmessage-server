//
//  SystemHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-16.
//

import Foundation
import IOKit.pwr_mgt
import MachO

private var sleepAssertionID: IOPMAssertionID = 0

func lockSystemSleep() {
	IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "AirMessage runs as a background service" as CFString, &sleepAssertionID)
}

func releaseSystemSleep() {
	IOPMAssertionRelease(sleepAssertionID)
}

/**
 Gets if this process is translated by Rosetta.
 Defaults to returning false if an error occurs.
 */
func isProcessTranslated() -> Bool {
	var ret: Int32 = 0
	var size = MemoryLayout.size(ofValue: ret)
	sysctlbyname("sysctl.proc_translated", &ret, &size, nil, 0)
	return ret == 1
}

/**
 Gets a string representation of the current computer architecture
 */
func getSystemArchitecture() -> String {
	let info = NXGetLocalArchInfo()
	return String(utf8String: (info?.pointee.description)!)!
}