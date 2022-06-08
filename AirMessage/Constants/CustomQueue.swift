//
//  CustomQueue.swift
//  AirMessage
//
//  Created by Cole Feuer on 2022-06-08.
//

import Foundation

class CustomQueue {
	static let timerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".task.timer", qos: .utility)
	static let timerQueueKey = DispatchSpecificKey<Bool>()
	
	static func register() {
		timerQueue.setSpecific(key: timerQueueKey, value: true)
	}
}
