//
//  LetsEncryptURLSessionDelegate.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-30.
//

import Foundation

//https://developer.apple.com/forums/thread/77694?answerId=229390022#229390022

/**
 A URL session delegate that accepts the new Let's Encrypt root certificate.
 This is required, since older Mac computers will not trust this certificate by default.
 */
class LetsEncryptURLSessionDelegate: NSObject, URLSessionDelegate {
	public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			//Get the Let's Encrypt root certificate (https://letsencrypt.org/certs)
			let rootCert = loadCertificate(named: "isrg-root-x1-cross-signed")
			
			//We override server trust evaluation (`NSURLAuthenticationMethodServerTrust`) to allow the
			//server to use a custom root certificate (`isrgrootx1.der`).
			let trust = challenge.protectionSpace.serverTrust!
			if evaluateCertificate(allowing: [rootCert], for: trust) {
				completionHandler(.useCredential, URLCredential(trust: trust))
			} else {
				completionHandler(.cancelAuthenticationChallenge, nil)
			}
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}
}
