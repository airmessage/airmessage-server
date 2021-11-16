//
//  AtomicBool.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

import Foundation

/**
 A simple wrapper for a thread-safe boolean protected by a read-write lock
 */
class AtomicBool {
	private let lock = ReadWriteLock()
	private var _value: Bool
	public var value: Bool {
		get {
			lock.withReadLock {
				return _value
			}
		}
		set {
			lock.withWriteLock {
				_value = newValue
			}
		}
	}
	
	init(initialValue: Bool = false) {
		_value = initialValue
	}
	
	/**
	 Helper function that returns an inout for more advanced operations
	 */
	@discardableResult
	public func with<Result>(_ body: (inout Bool) throws -> Result) rethrows -> Result {
		try lock.withWriteLock {
			try body(&_value)
		}
	}
}
