//
//  AccountConnectViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import AppKit
import AuthenticationServices
import Swifter

private let jsFuncConfirm = "confirmHandler"

class AccountConnectViewController: NSViewController {
	@IBOutlet weak var cancelButton: NSButton!
	@IBOutlet weak var loadingProgressIndicator: NSProgressIndicator!
	@IBOutlet weak var loadingLabel: NSTextField!
	
	private var server: HttpServer!
	
	private var _currentAuthSession: Any? = nil
	@available(macOS 10.15, *)
	fileprivate var currentAuthSession: ASWebAuthenticationSession? {
		get { _currentAuthSession as! ASWebAuthenticationSession? }
		set { _currentAuthSession = newValue }
	}
	
	private var isConnecting = false
	private var currentDataProxy: DataProxyConnect!
	private var currentUserID: String!
	private var currentEmailAddress: String!
	
	public var onAccountConfirm: ((_ userID: String, _ emailAddress: String) -> Void)?
	
	override func viewDidLoad() {
		//Prevent resizing
		preferredContentSize = view.frame.size
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Start the HTTP server
		server = HttpServer()
		
		server["/"] = shareFile(Bundle.main.resourcePath! + "/build/index.html")
		server["/:path"] = shareFilesFromDirectory(Bundle.main.resourcePath! + "/build")
		server.POST["/method"] = { request in
			if #available(macOS 10.15, *) {
				return .ok(.text("scheme"))
			} else {
				return .ok(.text("post"))
			}
		}
		server.POST["/submit"] = { request in
			//Get the refresh token
			guard let refreshToken = request.queryParams.first(where: { $0.0 == "refreshToken" })?.1 else {
				LogManager.log("Ignoring invalid /submit request", level: .notice)
				return .badRequest(nil)
			}
			
			//Start connecting
			DispatchQueue.main.async {
				NSApp.activate(ignoringOtherApps: true)
				self.startConnection(refreshToken: refreshToken)
			}
			
			//Return OK
			return .ok(.data(Data(), contentType: nil))
		}
		try! server.start(0)
		let port = try! server.port()
		
		LogManager.log("Running local server on http://localhost:\(port)", level: .info)
		
		let url = URL(string:"http://localhost:\(port)")!
		if #available(macOS 10.15, *) {
			//Open URL in an authentication session
			let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "airmessageauth") { [weak self] callbackURL, error in
				DispatchQueue.main.async {
					guard let self = self, self.view.window != nil else { return }
					
					//Remove the session
					self.currentAuthSession = nil
					
					//Check the response
					guard error == nil, let callbackURL = callbackURL else {
						self.dismiss(self)
						return
					}
					
					//Parse the URL
					guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
						  let scheme = components.scheme,
						  let params = components.queryItems else {
							  LogManager.log("Unable to parse authentication response URL: \(url)", level: .notice)
							  self.dismiss(self)
							  return
						  }
					
					//Check for authentication
					guard scheme == "airmessageauth",
						  components.path == "firebase",
						  let refreshToken = params.first(where: { $0.name == "refreshToken" })?.value else {
							  LogManager.log("Unable to validate authentication response URL: \(url)", level: .notice)
							  self.dismiss(self)
							  return
						  }
					
					//Start connecting
					self.startConnection(refreshToken: refreshToken)
				}
			}
			session.presentationContextProvider = self
			session.start()
			currentAuthSession = session
		} else {
			//Open URL in the default web browser
			NSWorkspace.shared.open(url)
		}
		
		//Update the view
		setLoading(false)
		loadingProgressIndicator.startAnimation(self)
		
		//Register for authentication and connection updates
		NotificationCenter.default.addObserver(self, selector: #selector(onAuthenticate), name: NotificationNames.authenticate, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateServerState), name: NotificationNames.updateServerState, object: nil)
	}
	
	override func viewDidDisappear() {
		//Stop the HTTP server
		server.stop()
		
		//Remove update listeners
		NotificationCenter.default.removeObserver(self)
		
		//Cancel the authentication session
		if #available(macOS 10.15, *) {
			currentAuthSession?.cancel()
		}
	}
	
	/**
	 Sets the view controller's views to reflect the loading state
	 */
	private func setLoading(_ loading: Bool) {
		cancelButton.isEnabled = !loading
		loadingLabel.isHidden = !loading
	}
	
	private func startConnection(refreshToken: String) {
		//Set the loading state
		setLoading(true)
		
		//Exchange the refresh token
		exchangeFirebaseRefreshToken(refreshToken) { [weak self] result, error in
			DispatchQueue.main.async {
				guard let self = self else { return }
				
				//Check for errors
				if let error = error {
					LogManager.log("Failed to exchange refresh token: \(error)", level: .info)
					self.showError(message: NSLocalizedString("message.register.error.sign_in", comment: ""), showReconnect: false)
					return
				}
				
				//If the error is nil, the result can't be nil
				let result = result!
				let userID = result.userId
				let idToken = result.idToken
				
				//Get the user info
				getFirebaseUserData(idToken: idToken) { [weak self] result, error in
					DispatchQueue.main.async {
						guard let self = self else { return }
						
						//Check for errors
						if let error = error {
							LogManager.log("Failed to get user data: \(error)", level: .info)
							self.showError(message: NSLocalizedString("message.register.error.sign_in", comment: ""), showReconnect: false)
							return
						}
						
						let result = result!
						guard !result.users.isEmpty else {
							LogManager.log("Failed to get user data: no users returned", level: .info)
							self.showError(message: NSLocalizedString("message.register.error.sign_in", comment: ""), showReconnect: false)
							return
						}
						let user = result.users[0]
						
						//Set the data proxy and connect
						self.isConnecting = true
						self.currentUserID = userID
						self.currentEmailAddress = user.email
						
						let proxy = DataProxyConnect(userID: userID, idToken: idToken)
						self.currentDataProxy = proxy
						ConnectionManager.shared.setProxy(proxy)
						ConnectionManager.shared.start()
					}
				}
			}
		}
	}
	
	/**
	 Shows an alert dialog that informs the user of a successful connection
	 */
	private func showSuccess() {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = NSLocalizedString("message.register.success.title", comment: "")
		alert.informativeText = NSLocalizedString("message.register.success.description", comment: "")
		alert.beginSheetModal(for: view.window!) { response in
			self.dismiss(self)
			self.onAccountConfirm?(self.currentUserID, self.currentEmailAddress)
		}
	}
	
	/**
	 Shows an alert dialog that informs the user of an error
	 - Parameters:
	   - message: The message to display to the user
	   - showReconnect: Whether to show a retry button that restarts the server
	 */
	private func showError(message: String, showReconnect: Bool) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = NSLocalizedString("message.register.error.title", comment: "")
		alert.informativeText = message
		if showReconnect {
			alert.addButton(withTitle: NSLocalizedString("action.retry", comment: ""))
		}
		alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: ""))
		alert.beginSheetModal(for: view.window!) { response in
			if response == .alertFirstButtonReturn {
				//Reconnect and try again
				self.isConnecting = true
				ConnectionManager.shared.start()
			} else {
				//Dismiss the dialog
				self.dismiss(self)
			}
		}
	}
	
	@objc private func onAuthenticate(notification: NSNotification) {
		let refreshToken = notification.userInfo![NotificationNames.authenticateParam] as! String
		startConnection(refreshToken: refreshToken)
	}
	
	@objc private func onUpdateServerState(notification: NSNotification) {
		guard isConnecting else { return }
		
		let serverState = ServerState(rawValue: notification.userInfo![NotificationNames.updateServerStateParam] as! Int)!
		if serverState == .running {
			//Set the data proxy as registered
			self.currentDataProxy.setRegistered()
			
			//Show a success dialog and close the view
			showSuccess()
			
			isConnecting = false
		} else if serverState.isError {
			//Show an error dialog
			showError(message: serverState.description, showReconnect: serverState.recoveryType == .retry)
			
			isConnecting = false
		}
	}
}

@available(macOS 10.15, *)
extension AccountConnectViewController: ASWebAuthenticationPresentationContextProviding {
	func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		return view.window!
	}
}
