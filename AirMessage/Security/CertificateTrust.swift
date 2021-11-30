//
//  CertificateTrust.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-30.
//

import Foundation

/**
 Loads a certificate from the bundle
 */
func loadCertificate(named name: String) -> SecCertificate {
	let cerURL = Bundle.main.url(forResource: name, withExtension: "der")!
	let cerData = try! Data(contentsOf: cerURL)
	let cer = SecCertificateCreateWithData(nil, cerData as CFData)!
	return cer
}

/**
 Evaluates the trust against the root certificates
 */
func evaluateCertificate(allowing rootCertificates: [SecCertificate], for trust: SecTrust) -> Bool {
	//Apply our custom root to the trust object.
	var err = SecTrustSetAnchorCertificates(trust, rootCertificates as CFArray)
	guard err == errSecSuccess else { return false }

	//Re-enable the system's built-in root certificates.
	err = SecTrustSetAnchorCertificatesOnly(trust, false)
	guard err == errSecSuccess else { return false }

	//Run a trust evaluation and only allow the connection if it succeeds.
	var trustResult: SecTrustResultType = .invalid
	err = SecTrustEvaluate(trust, &trustResult)
	guard err == errSecSuccess else { return false }
	return [.proceed, .unspecified].contains(trustResult)
}
