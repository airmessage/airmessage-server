//
//  ReadWriteLock.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

import Foundation

class ReadWriteLock {
	private var lock: pthread_rwlock_t
	
	init() {
		lock = pthread_rwlock_t()
		pthread_rwlock_init(&lock, nil)
	}
	
	deinit {
		pthread_rwlock_destroy(&lock)
	}
	
	@discardableResult
	public func withReadLock<Result>(_ body: () throws -> Result) rethrows -> Result {
		pthread_rwlock_rdlock(&lock)
		defer { pthread_rwlock_unlock(&lock) }
		return try body()
	}
	
	@discardableResult
	public func withWriteLock<Return>(_ body: () throws -> Return) rethrows -> Return {
		pthread_rwlock_wrlock(&lock)
		defer { pthread_rwlock_unlock(&lock) }
		return try body()
	}
}
