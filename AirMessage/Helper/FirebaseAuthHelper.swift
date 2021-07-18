//
//  FirebaseAuthHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-18.
//

import Foundation

//https://firebase.google.com/docs/reference/rest/auth

private var timeSeconds: Int {
	get {
		Int(NSDate().timeIntervalSinceReferenceDate)
	}
}

class FirebaseAuthHelper: NSObject {
	public static let shared = FirebaseAuthHelper()
	@objc class func getShared() -> FirebaseAuthHelper { shared }
	
	private let cacheSerialQueue = DispatchQueue(label: "FirebaseAuthHelper")
	private var cachedIDToken: CachedIDToken?
	
	@objc func getIDToken() throws -> String {
		//Checking if we have a cached value that's still valid
		if let cachedIDToken = runOnMain(execute: { () -> String? in
			if let cached = self.cachedIDToken, timeSeconds < cached.expiry {
				//Return the cached value
				return cached.idToken
			} else {
				return nil
			}
		}) {
			return cachedIDToken
		}
		
		//Get the refresh token
		let refreshToken = PreferencesManager.shared.refreshToken
		
		//Send the request
		guard let requestBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8) else {
			throw FirebaseAuthError.serializationError
		}
		
		let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Bundle.main.infoDictionary!["FIREBASE_API_KEY"] as! String)")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		
		var requestResult: FirebaseTokenResult?
		var requestError: FirebaseAuthError?
		let semaphore = DispatchSemaphore(value: 0)
		let task = URLSession.shared.uploadTask(with: request, from: requestBody) { data, response, error in
			if let error = error {
				requestError = FirebaseAuthError.requestError(cause: error)
				return
			}
			
			guard let response = response as? HTTPURLResponse else {
				requestError = FirebaseAuthError.serverError(code: nil)
				return
			}
			
			guard (200...299).contains(response.statusCode) else {
				requestError = FirebaseAuthError.serverError(code: response.statusCode)
				
				if let data = data,
				   let dataString = String(data: data, encoding: .utf8) {
					print("Request error: \(dataString)")
				}
				return
			}
			
			guard let mimeType = response.mimeType,
				  mimeType == "application/json",
				  let data = data else {
				requestError = FirebaseAuthError.responseError
				return
			}
			
			guard let result = try? JSONDecoder().decode(FirebaseTokenResult.self, from: data) else {
				requestError = FirebaseAuthError.deserializationError
				return
			}
			
			requestResult = result
			semaphore.signal()
		}
		//Run request synchronously
		task.resume()
		semaphore.wait()
		
		if let error = requestError {
			throw error
		}
		
		//Save the cached value
		if let expiresIn = Int(requestResult!.expires_in) {
			runOnMainAsync {
				self.cachedIDToken = CachedIDToken(idToken: requestResult!.id_token, expiry: timeSeconds + expiresIn)
			}
		}
		
		//Return the ID token
		return requestResult!.id_token
	}
}

private struct FirebaseTokenResult: Codable {
	let expires_in: String
	let token_type: String
	let refresh_token: String
	let id_token: String
	let user_id: String
	let project_id: String
}

private struct CachedIDToken {
	let idToken: String
	let expiry: Int
}

enum FirebaseAuthError: Error {
	case serializationError
	case deserializationError
	case serverError(code: Int?)
	case requestError(cause: Error)
	case responseError
	
	public var errorDescription: String {
		switch self {
			case .serializationError:
				return "Data serialization error"
			case .deserializationError:
				return "Data deserialization error"
			case .serverError(let code):
				if let code = code {
					return "Server error: response code \(code)"
				} else {
					return "Server error"
				}
			case .requestError(let error):
				return "Request error: \(error.localizedDescription)"
			case .responseError:
				return "Error reading response"
		}
	}
}
