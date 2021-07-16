//
//  SystemHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-16.
//

import Foundation
import IOKit.pwr_mgt

private var sleepAssertionID: IOPMAssertionID = 0

func lockSystemSleep() {
	IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "AirMessage runs as a background service" as CFString, &sleepAssertionID)
}

func releaseSystemSleep() {
	IOPMAssertionRelease(sleepAssertionID)
}
