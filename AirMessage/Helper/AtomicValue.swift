//
//  AtomicValue.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

import Foundation

/**
 A simple wrapper for a thread-safe value protected by a read-write lock
 */
class AtomicValue<Value> {
	private let lock = ReadWriteLock()
	private var _value: Value
	public var value: Value {
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
	
	init(initialValue: Value) {
		_value = initialValue
	}
	
	/**
	 Helper function that returns an inout for more advanced operations
	 */
	@discardableResult
	public func with<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
		try lock.withWriteLock {
			try body(&_value)
		}
	}
}

typealias AtomicBool = AtomicValue<Bool>
