//
//  ForwardCompatURLSessionDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-30.
//

import Foundation

//https://developer.apple.com/forums/thread/77694?answerId=229390022#229390022

/**
 A URL session delegate that accepts more modern root certificates.
 This is required, since older Mac computers will not trust these certificates by default.
 */
class ForwardCompatURLSessionDelegate: NSObject, URLSessionDelegate {
	public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		#if DEBUG
			LogManager.log("Evaluating host \(challenge.protectionSpace.host) for \(challenge.protectionSpace.authenticationMethod)", level: .debug)
		#endif
		
		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			//Get all local root certificates
			let certificates = loadBundleCertificates()
			
			//We override server trust evaluation (`NSURLAuthenticationMethodServerTrust`) to allow the
			//server to use a custom root certificate (`isrgrootx1.der`).
			let trust = challenge.protectionSpace.serverTrust!
			if evaluateCertificate(allowing: certificates, for: trust) {
				completionHandler(.useCredential, URLCredential(trust: trust))
			} else {
				completionHandler(.cancelAuthenticationChallenge, nil)
			}
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}
}
