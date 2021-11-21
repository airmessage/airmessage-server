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
	private var server: HttpServer!
	
	public var onAccountConfirm: ((_ refreshToken: String) -> Void)?
	
	override func viewDidLoad() {
		//Initializing the WebView
		let webView = WKWebView()
		webView.frame = CGRect(x: 20, y: 60, width: 450, height: 450)
		view.addSubview(webView)
		
		let contentController = webView.configuration.userContentController
		contentController.add(self, name: jsFuncConfirm)
		
		webView.layer!.borderWidth = 1
		webView.layer!.borderColor = NSColor.lightGray.cgColor
		
		server = HttpServer()
		
		server["/"] = shareFile(Bundle.main.resourcePath! + "/build/index.html")
		server["/:path"] = shareFilesFromDirectory(Bundle.main.resourcePath! + "/build")
		try! server.start(0)
		let port = try! server.port()
		
		LogManager.log("Running local server on http://localhost:\(port)", level: .info)
		webView.load(URLRequest(url: URL(string:"http://localhost:\(port)")!))
	}
	
	override func viewDidDisappear() {
		server.stop()
	}
}

extension AccountConnectViewController: WKScriptMessageHandler {
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == jsFuncConfirm {
			let dict = message.body as! [String: String]
			
			onAccountConfirm?(dict["refreshToken"]!)
			dismiss(self)
		}
	}
}
