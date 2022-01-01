//
// Created by Cole Feuer on 2021-10-03.
//

import Foundation
import AppKit
import WebKit
import Ink
import Zip

class SoftwareUpdateViewController: NSViewController {
	//Outlets
	@IBOutlet weak var descriptionLabel: NSTextField!
	@IBOutlet weak var webViewContainer: NSView!
	
	//Parameters
	public var updateData: UpdateStruct!
	
	//State
	private var sheetController: SoftwareUpdateProgressViewController?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		
		//Create the WebView
		let webView = WKWebView()
		webView.frame = webViewContainer.bounds
		webView.navigationDelegate = self
		webView.wantsLayer = true
		webView.layer!.borderWidth = 1
		webView.layer!.borderColor = NSColor.lightGray.cgColor
		webViewContainer.addSubview(webView)
		webViewContainer.autoresizesSubviews = true
		
		//Load the update notes
		let parser = MarkdownParser()
		let notesHTML = """
						<meta name="color-scheme" content="dark light">
						<span style="font-family: sans-serif; font-size: \(NSFont.systemFontSize)">
						\(parser.html(from: updateData.notes))
						</span>
						"""
		webView.loadHTMLString(notesHTML, baseURL: nil)
		
		//Set the update description
		descriptionLabel.stringValue = String(format: NSLocalizedString("message.update.available", comment: ""), updateData.versionName, Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.software_update", comment: "")
	}
	
	@IBAction func onRemindLater(_ sender: Any) {
		//Close window
		view.window!.close()
	}
	
	@IBAction func onInstallUpdate(_ sender: Any) {
		if updateData.downloadType == .external {
			//Open the URL
			NSWorkspace.shared.open(updateData.downloadURL)
			
			//Close the window
			view.window!.close()
		} else {
			//Start installing the update
			let updateStarted = UpdateHelper.install(
					update: updateData,
					onProgress: { [weak self] progress in
						if let sheetController = self?.sheetController {
							//Update the progress bar
							sheetController.progressIndicator.doubleValue = progress
						}
					},
					onSuccess: { [weak self] in
						guard let self = self else { return }
						
						//Dismiss the sheet
						if let theSheetController = self.sheetController {
							self.dismiss(theSheetController)
							self.sheetController = nil
						}
						
						//Close the window
						self.view.window!.close()
					},
					onError: { [weak self] code, description in
						guard let self = self else { return }
						
						//Dismiss the sheet
						if let theSheetController = self.sheetController {
							self.dismiss(theSheetController)
							self.sheetController = nil
						}
						
						//Show an alert
						let alertMessage: String
						switch code {
							case .download:
								alertMessage = NSLocalizedString("message.update.error.download", comment: "")
							case .badPackage:
								alertMessage = NSLocalizedString("message.update.error.invalid_package", comment: "")
							case .internalError:
								alertMessage = NSLocalizedString("message.update.error.internal", comment: "")
						}
						
						let alert = NSAlert()
						alert.alertStyle = .critical
						alert.messageText = alertMessage
						alert.beginSheetModal(for: self.view.window!)
					}
			)
			
			if updateStarted {
				//Show a progress popup
				let storyboard = NSStoryboard(name: "Main", bundle: nil)
				let windowController = storyboard.instantiateController(withIdentifier: "SoftwareUpdateProgress") as! SoftwareUpdateProgressViewController
				presentAsSheet(windowController)
				sheetController = windowController
			}
		}
	}
}

extension SoftwareUpdateViewController: WKNavigationDelegate {
	//Open clicked links in the browser
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
			NSWorkspace.shared.open(url)
			decisionHandler(.cancel)
		} else if navigationAction.navigationType == .reload {
			decisionHandler(.cancel)
		} else {
			decisionHandler(.allow)
		}
	}
}
