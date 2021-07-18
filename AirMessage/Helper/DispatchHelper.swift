//
//  DispatchHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-18.
//

import Foundation

func runOnMain<T>(execute work: () throws -> T) rethrows -> T {
	if Thread.isMainThread {
		return try work()
	} else {
		return try DispatchQueue.main.sync(execute: work)
	}
}

func runOnMainAsync(execute work: @escaping () -> Void) {
	if Thread.isMainThread {
		work()
	} else {
		DispatchQueue.main.async(execute: work)
	}
}
