//
//  AssertionHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2022-05-31.
//

import Foundation

/// Adds a debug assertion that the code is being run on the passed dispatch queue
func assertDispatchQueue(_ queue: DispatchQueue) {
	#if DEBUG
		if #available(macOS 10.12, *) {
			dispatchPrecondition(condition: .onQueue(queue))
		}
	#endif
}
