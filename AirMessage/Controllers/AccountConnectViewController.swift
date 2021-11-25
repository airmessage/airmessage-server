//
//  AccountConnectViewController.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import AppKit
import WebKit
import Swifter

private let jsFuncConfirm = "confirmHandler"

class AccountConnectViewController: NSViewController {
	@IBOutlet weak var cancelButton: NSButton!
	@IBOutlet weak var loadingProgressIndicator: NSProgressIndicator!
	@IBOutlet weak var loadingLabel: NSTextField!
	private var webView: WKWebView!
	
	private var server: HttpServer!
	
	private var isConnecting = false
	private var currentDataProxy: DataProxyConnect!
	private var currentUserID: String!
	
	public var onAccountConfirm: ((_ userID: String) -> Void)?
	
	override func viewDidLoad() {
		//Prevent resizing
		preferredContentSize = view.frame.size
		
		//Initialize the WebView
		webView = WKWebView()
		webView.frame = CGRect(x: 20, y: 60, width: 450, height: 450)
		view.addSubview(webView)
		
		let contentController = webView.configuration.userContentController
		contentController.add(self, name: jsFuncConfirm)
		
		webView.layer!.borderWidth = 1
		webView.layer!.borderColor = NSColor.lightGray.cgColor
		
		//Start the HTTP server
		server = HttpServer()
		
		server["/"] = shareFile(Bundle.main.resourcePath! + "/build/index.html")
		server["/:path"] = shareFilesFromDirectory(Bundle.main.resourcePath! + "/build")
		try! server.start(0)
		let port = try! server.port()
		
		LogManager.log("Running local server on http://localhost:\(port)", level: .info)
		webView.load(URLRequest(url: URL(string:"http://localhost:\(port)")!))
		
		//Update the view
		setLoading(false)
		
		//Register for connection updates
		NotificationCenter.default.addObserver(self, selector: #selector(onUpdateServerState), name: NotificationNames.updateServerState, object: nil)
	}
	
	override func viewDidDisappear() {
		//Stop the HTTP server
		server.stop()
		
		//Remove update listeners
		NotificationCenter.default.removeObserver(self)
	}
	
	/**
	 Sets the view controller's views to reflect the loading state
	 */
	private func setLoading(_ loading: Bool) {
		cancelButton.isEnabled = !loading
		loadingProgressIndicator.isHidden = !loading
		if loading {
			loadingProgressIndicator.startAnimation(self)
		} else {
			loadingProgressIndicator.stopAnimation(self)
		}
		loadingLabel.isHidden = !loading
		webView.isHidden = loading
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
				
				//Set the data proxy and connect
				self.isConnecting = true
				self.currentUserID = result.userId
				
				let proxy = DataProxyConnect(installationID: PreferencesManager.shared.installationID, userID: result.userId, idToken: result.idToken)
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
			self.onAccountConfirm?(self.currentUserID)
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
			if response == .alertSecondButtonReturn {
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

extension AccountConnectViewController: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == jsFuncConfirm {
			let dict = message.body as! [String: String]
			startConnection(refreshToken: dict["refreshToken"]!)
		}
	}
}
