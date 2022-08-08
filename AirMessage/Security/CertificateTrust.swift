//
//  CertificateTrust.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-30.
//

import Foundation

class CertificateTrust {
	///An array of all certificate files
	static var certificateFiles: [URL] = {
		let certificatesDir = Bundle.main.resourceURL!.appendingPathComponent("Certificates", isDirectory: true)
		return try! FileManager.default.contentsOfDirectory(at: certificatesDir, includingPropertiesForKeys: nil)
	}()
	
	///All locally-stored certificates
	static var secCertificates: [SecCertificate] = {
		return certificateFiles.map { fileURL in
			SecCertificateCreateWithData(nil, try! Data(contentsOf: fileURL) as CFData)!
		}
	}()

	///Evaluates the trust against the root certificates
	static func evaluateCertificate(allowing rootCertificates: [SecCertificate], for trust: SecTrust) -> Bool {
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
}
