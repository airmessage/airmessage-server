//
//  FirebaseAuthHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-18.
//

import Foundation

//https://firebase.google.com/docs/reference/rest/auth

private let apiKey = Bundle.main.infoDictionary!["FIREBASE_API_KEY"] as! String

///Exchanges an IDP token for a Firebase token
func exchangeFirebaseIDPToken(_ idToken: String, providerID: String, callbackURL: String, callback: @escaping (_ result: FirebaseIDPExchangeResult?, _ error: Error?) -> Void) {
	//Send the request
	let requestObject = FirebaseIDPExchangeRequest(
		requestUri: callbackURL,
		postBody: "id_token=\(idToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)&providerId=\(providerID.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)",
		returnSecureToken: true,
		returnIdpCredential: false
	)
	
	let requestBody: Data
	do {
		requestBody = try JSONEncoder().encode(requestObject)
	} catch {
		callback(nil, error)
		return
	}
	
	let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)")!
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	
	let task = URLSession.sharedCompat.uploadTask(with: request, from: requestBody) { data, response, error in
		if let error = error {
			callback(nil, FirebaseRequestError.requestError(cause: error))
			return
		}
		
		guard let response = response as? HTTPURLResponse else {
			callback(nil, FirebaseRequestError.serverError(code: nil))
			return
		}
		
		guard (200...299).contains(response.statusCode) else {
			if let data = data,
			   let dataString = String(data: data, encoding: .utf8) {
				LogManager.log("Firebase authentication request error: \(dataString)", level: .error)
			}
			
			callback(nil, FirebaseRequestError.serverError(code: response.statusCode))
			return
		}
		
		guard let mimeType = response.mimeType,
			  mimeType == "application/json",
			  let data = data else {
			callback(nil, FirebaseRequestError.responseError)
			return
		}
		
		guard let result = try? JSONDecoder().decode(FirebaseIDPExchangeResult.self, from: data) else {
			callback(nil, FirebaseRequestError.deserializationError)
			return
		}
		
		//Return the result
		callback(result, nil)
	}
	task.resume()
}

/**
 Exchanges a Firebase refresh token for information about the user
 */
func exchangeFirebaseRefreshToken(_ refreshToken: String, callback: @escaping (_ result: FirebaseTokenResult?, _ error: Error?) -> Void) {
	//Send the request
	guard let requestBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8) else {
		callback(nil, FirebaseRequestError.serializationError)
		return
	}
	
	let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
	
	let task = URLSession.sharedCompat.uploadTask(with: request, from: requestBody) { data, response, error in
		if let error = error {
			callback(nil, FirebaseRequestError.requestError(cause: error))
			return
		}
		
		guard let response = response as? HTTPURLResponse else {
			callback(nil, FirebaseRequestError.serverError(code: nil))
			return
		}
		
		guard (200...299).contains(response.statusCode) else {
			if let data = data,
			   let dataString = String(data: data, encoding: .utf8) {
				LogManager.log("Firebase authentication request error: \(dataString)", level: .error)
			}
			
			callback(nil, FirebaseRequestError.serverError(code: response.statusCode))
			return
		}
		
		guard let mimeType = response.mimeType,
			  mimeType == "application/json",
			  let data = data else {
			callback(nil, FirebaseRequestError.responseError)
			return
		}
		
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let result = try? decoder.decode(FirebaseTokenResult.self, from: data) else {
			callback(nil, FirebaseRequestError.deserializationError)
			return
		}
		
		//Return the result
		callback(result, nil)
	}
	task.resume()
}

func getFirebaseUserData(idToken: String, callback: @escaping (_ result: FirebaseUserDataResult?, _ error: Error?) -> Void) {
	//Send the request
	guard let requestBody = "{\"idToken\":\"\(idToken)\"}".data(using: .utf8) else {
		callback(nil, FirebaseRequestError.serializationError)
		return
	}
	
	let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(apiKey)")!
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.setValue("application/json", forHTTPHeaderField: "Content-Type")
	
	let task = URLSession.sharedCompat.uploadTask(with: request, from: requestBody) { data, response, error in
		if let error = error {
			callback(nil, FirebaseRequestError.requestError(cause: error))
			return
		}
		
		guard let response = response as? HTTPURLResponse else {
			callback(nil, FirebaseRequestError.serverError(code: nil))
			return
		}
		
		guard (200...299).contains(response.statusCode) else {
			if let data = data,
			   let dataString = String(data: data, encoding: .utf8) {
				LogManager.log("Firebase user info request error: \(dataString)", level: .error)
			}
			
			callback(nil, FirebaseRequestError.serverError(code: response.statusCode))
			return
		}
		
		guard let mimeType = response.mimeType,
			  mimeType == "application/json",
			  let data = data else {
			callback(nil, FirebaseRequestError.responseError)
			return
		}
		
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		guard let result = try? decoder.decode(FirebaseUserDataResult.self, from: data) else {
			callback(nil, FirebaseRequestError.deserializationError)
			return
		}
		
		//Return the result
		callback(result, nil)
	}
	task.resume()
}

struct FirebaseIDPExchangeRequest: Encodable {
	let requestUri: String
	let postBody: String
	let returnSecureToken: Bool
	let returnIdpCredential: Bool
}

struct FirebaseIDPExchangeResult: Decodable {
	let idToken: String
	let refreshToken: String
	let expiresIn: String
	let localId: String
	let email: String
}

struct FirebaseTokenResult: Decodable {
	let expiresIn: String
	let tokenType: String
	let refreshToken: String
	let idToken: String
	let userId: String
	let projectId: String
}

struct FirebaseUserDataResult: Decodable {
	let users: [FirebaseUserDataResultEntry]
}

struct FirebaseUserDataResultEntry: Decodable {
	let localId: String
	let email: String
	let displayName: String
}

enum FirebaseRequestError: Error {
	case serializationError
	case deserializationError
	case serverError(code: Int?)
	case requestError(cause: Error)
	case responseError
	
	public var errorDescription: String? {
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
