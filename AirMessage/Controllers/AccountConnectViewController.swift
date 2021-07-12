//
//  NativeStorage.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import AppKit
import WebKit
import Swifter

class AccountConnectViewController: NSViewController {
	var server: HttpServer!
	
	var onAccountConfirm: ((_ idToken: String, _ userID: String) -> Void)?
	
	private let jsFuncConfirm = "confirmHandler"
	private let jsFuncError = "errorHandler"
	
	override func viewDidLoad() {
		//Initializing the WebView
		let webView = WKWebView()
		webView.frame = CGRect(x: 20, y: 60, width: 450, height: 450)
		view.addSubview(webView)
		
		let contentController = webView.configuration.userContentController
		contentController.add(self, name: jsFuncConfirm)
		contentController.add(self, name: jsFuncError)
		
		webView.layer!.borderWidth = 1
		webView.layer!.borderColor = NSColor.lightGray.cgColor
		
		server = HttpServer()
		
		server["/"] = shareFile(Bundle.main.resourcePath! + "/build/index.html")
		server["/:path"] = shareFilesFromDirectory(Bundle.main.resourcePath! + "/build")
		//server[":path"] = { .ok(.htmlBody("You asked for \($0)"))  }
		try! server.start(0)
		
		print("Running local server on http://localhost:\(try! server.port())")
		webView.load(URLRequest(url: URL(string:"http://localhost:\(try! server.port())")!))
	}
	
	override func viewDidDisappear() {
		server.stop()
	}
}

extension AccountConnectViewController: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == jsFuncConfirm {
			guard let dict = message.body as? [String: String] else {
				return
			}
			
			print(dict)
			
			onAccountConfirm?(dict["idToken"]!, dict["userID"]!)
			dismiss(self)
		} else if message.name == jsFuncError {
			guard let dict = message.body as? [String: String] else {
				return
			}
			
			print(dict)
		}
	}
}
