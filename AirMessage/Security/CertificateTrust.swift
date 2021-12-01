//
//  CertificateTrust.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-30.
//

import Foundation

/**
 Gets all locally-stored certificates
 */
func loadBundleCertificates() -> [SecCertificate] {
	//Get all local root certificates
	let certificatesDir = URL(string: Bundle.main.resourcePath!)!.appendingPathComponent("Certificates", isDirectory: true)
	let certificates = try! FileManager.default.contentsOfDirectory(at: certificatesDir, includingPropertiesForKeys: nil)
		.map { fileURL in
			SecCertificateCreateWithData(nil, try! Data(contentsOf: fileURL) as CFData)!
	}
	return certificates
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
