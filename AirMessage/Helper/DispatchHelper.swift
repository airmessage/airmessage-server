//
//  DispatchHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-18.
//

import Foundation

/**
 Runs work on the main thread synchronously, skipping the dispatch queue if we're already on the main thread
 */
func runOnMain<T>(execute work: () throws -> T) rethrows -> T {
	if Thread.isMainThread {
		return try work()
	} else {
		return try DispatchQueue.main.sync(execute: work)
	}
}

/**
 Runs work on the main thread asynchronously, skipping the dispatch queue if we're already on the main thread
 */
func runOnMainAsync(execute work: @escaping () -> Void) {
	if Thread.isMainThread {
		work()
	} else {
		DispatchQueue.main.async(execute: work)
	}
}
