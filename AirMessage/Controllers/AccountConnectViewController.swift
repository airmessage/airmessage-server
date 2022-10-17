//
//  AccountConnectViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import AppKit
import AuthenticationServices
import AppAuth

private let oidServiceConfiguration = OIDServiceConfiguration(
	authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/auth")!,
	  tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
  )

class AccountConnectViewController: NSViewController {
	@IBOutlet weak var cancelButton: NSButton!
	@IBOutlet weak var loadingProgressIndicator: NSProgressIndicator!
	@IBOutlet weak var loadingLabel: NSTextField!
	
	let redirectHandler = OIDRedirectHTTPHandler(successURL: nil)
	
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
		var httpListenerError: NSError?
		let redirectURL = redirectHandler.startHTTPListener(&httpListenerError)
		if let httpListenerError = httpListenerError {
			try! { throw httpListenerError }()
		}
		
		//Start the authorization flow
		let request = OIDAuthorizationRequest(
			configuration: oidServiceConfiguration,
			clientId: (Bundle.main.infoDictionary!["GOOGLE_OAUTH_CLIENT_ID"] as! String),
			clientSecret: (Bundle.main.infoDictionary!["GOOGLE_OAUTH_CLIENT_SECRET"] as! String),
			scopes: [
				"openid",
				"https://www.googleapis.com/auth/userinfo.email",
				"profile"
			],
			redirectURL: redirectURL,
			responseType: "code",
			additionalParameters: ["prompt": "select_account"]
		)
		
		redirectHandler.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: view.window!) { [weak self] result, error in
			guard let self = self else { return }
			
			//Surface errors to the user
			if let error = error {
				self.showError(message: error.localizedDescription, showReconnect: false)
				return
			}
			
			//Start a connection with the ID token
			let idToken = result!.lastTokenResponse!.idToken!
			self.startConnection(idToken: idToken, callbackURL: redirectURL.absoluteString)
		}
		
		//Update the view
		setLoading(false)
		loadingProgressIndicator.startAnimation(self)
		
		//Register for authentication and connection updates
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateServerState), name: NotificationNames.updateServerState, object: nil)
	}
	
	override func viewDidDisappear() {
		//Stop the server
		redirectHandler.cancelHTTPListener()
		
		//Remove update listeners
		NotificationCenter.default.removeObserver(self)
	}
	
	/**
	 Sets the view controller's views to reflect the loading state
	 */
	private func setLoading(_ loading: Bool) {
		cancelButton.isEnabled = !loading
		loadingLabel.isHidden = !loading
	}
	
	private func startConnection(idToken: String, callbackURL: String) {
		//Set the loading state
		setLoading(true)
		
		//Exchange the refresh token
		exchangeFirebaseIDPToken(idToken, providerID: "google.com", callbackURL: callbackURL) { [weak self] result, error in
			DispatchQueue.main.async {
				guard let self = self else { return }
				
				//Check for errors
				if let error = error {
					LogManager.log("Failed to exchange IDP token: \(error)", level: .info)
					self.showError(message: NSLocalizedString("message.register.error.sign_in", comment: ""), showReconnect: false)
					return
				}
				
				//If the error is nil, the result can't be nil
				let result = result!
				let userID = result.localId
				let idToken = result.idToken
				
				//Set the data proxy and connect
				self.isConnecting = true
				self.currentUserID = result.localId
				self.currentEmailAddress = result.email
				
				let proxy = DataProxyConnect(userID: userID, idToken: idToken)
				self.currentDataProxy = proxy
				ConnectionManager.shared.setProxy(proxy)
				ConnectionManager.shared.start()
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
			if showReconnect && response == .alertFirstButtonReturn {
				//Reconnect and try again
				self.isConnecting = true
				ConnectionManager.shared.start()
			} else {
				//Dismiss the dialog
				self.dismiss(self)
			}
		}
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
