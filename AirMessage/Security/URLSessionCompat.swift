//
//  URLSessionCompat.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-12-01.
//

import Foundation

class URLSessionCompat {
	static let delegate = ForwardCompatURLSessionDelegate()
	static let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
}

extension URLSession {
	/**
	 A singleton `URLSession` with compatibility for older computers
	 */
	static var sharedCompat: URLSession { URLSessionCompat.session }
}
