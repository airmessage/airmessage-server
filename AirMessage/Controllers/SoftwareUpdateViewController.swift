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
	
	//Data
	private var urlSession: URLSession!
	
	//State
	private var sheetController: SoftwareUpdateProgressViewController?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		
		//Initialize URL session
		urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
		
		//Create the WebView
		let webView = WKWebView()
		webView.frame = webViewContainer.bounds
		webView.navigationDelegate = self
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
		
		//Focus app
		NSApp.activate(ignoringOtherApps: true)
	}
	
	override func viewDidDisappear() {
		super.viewDidDisappear()
		
		urlSession.invalidateAndCancel()
	}
	
	@IBAction func onRemindLater(_ sender: Any) {
		//Close window
		view.window!.close()
	}
	
	@IBAction func onInstallUpdate(_ sender: Any) {
		if updateData.downloadExternal {
			//Open the URL
			NSWorkspace.shared.open(updateData.downloadURL)
			
			//Close the window
			view.window!.close()
		} else {
			//Show a progress popup
			let storyboard = NSStoryboard(name: "Main", bundle: nil)
			let windowController = storyboard.instantiateController(withIdentifier: "SoftwareUpdateProgress") as! SoftwareUpdateProgressViewController
			presentAsSheet(windowController)
			sheetController = windowController
			
			//Download the file
			let task = urlSession.downloadTask(with: updateData.downloadURL)
			task.resume()
		}
	}
}

extension SoftwareUpdateViewController: URLSessionDownloadDelegate {
	private func showError(message: String) {
		DispatchQueue.main.async { [self] in
			//Dismiss the sheet
			if let theSheetController = sheetController {
				dismiss(theSheetController)
				sheetController = nil
			}
			
			//Show an alert
			let alert = NSAlert()
			alert.alertStyle = .critical
			alert.messageText = message
			alert.beginSheetModal(for: view.window!)
		}
	}
	
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		if let error = downloadTask.error {
			LogManager.shared.log("Can't apply update, download error: %{public}", type: .notice, error.localizedDescription)
			showError(message: error.localizedDescription)
			return
		}
		
		guard let httpResponse = downloadTask.response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
			LogManager.shared.log("Can't apply update, HTTP response error", type: .notice)
			showError(message: "Failed to download update")
			return
		}
		
		do {
			//Get Applications directory
			let destinationFolder = try FileManager.default.url(for: .applicationDirectory, in: .localDomainMask, appropriateFor: nil, create: false)
			
			//Get the temporary directory
			let temporaryDirectory = try FileManager.default.url(
					for: .itemReplacementDirectory,
					in: .userDomainMask,
					appropriateFor: destinationFolder,
					create: true
			)
			
			//Get the download targets
			let zippedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip", isDirectory: false)
			let unzippedFolder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
			
			//Move the downloaded file to a temporary location, and append the .zip extension
			try FileManager.default.moveItem(at: location, to: zippedFile)
			LogManager.shared.log("Downloaded and moved update file to %@", type: .info, zippedFile.path)
			
			//Unzip file
			try Zip.unzipFile(zippedFile, destination: unzippedFolder, overwrite: true, password: nil)
			LogManager.shared.log("Decompressed update file to %@", type: .info, unzippedFolder.path)
			
			//Find app file
			guard let updateAppFile = try FileManager.default.contentsOfDirectory(at: unzippedFolder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "app" }).first else {
				LogManager.shared.log("Can't apply update, can't find app file in update archive", type: .notice)
				showError(message: "Invalid update package received; please try again later")
				return
			}
			
			//Get target file in Applications
			let targetAppFile = destinationFolder.appendingPathComponent(updateAppFile.lastPathComponent, isDirectory: false)
			LogManager.shared.log("Targeting update location %@", type: .info, targetAppFile.path)
			
			//Delete old zip file
			try FileManager.default.removeItem(at: zippedFile)
			
			//Load the update script
			let updateScript = try! String(contentsOf: Bundle.main.url(forResource: "SoftwareUpdate", withExtension: "sh")!)
			
			//Start the update process
			let process = Process()
			process.arguments = ["-c", updateScript, String(ProcessInfo.processInfo.processIdentifier), updateAppFile.path, targetAppFile.path]
			if #available(macOS 10.13, *) {
				process.executableURL = URL(fileURLWithPath: "/bin/sh")
				try process.run()
			} else {
				process.launchPath = "/bin/sh"
				process.launch()
			}
			
			LogManager.shared.log("Started update process", type: .info)
			
			DispatchQueue.main.async { [self] in
				//Dismiss the sheet
				if let theSheetController = sheetController {
					dismiss(theSheetController)
					sheetController = nil
				}
				
				//Close the window
				view.window!.close()
				
				//Quit the app
				NSApplication.shared.terminate(self)
			}
		} catch {
			//Log the error
			LogManager.shared.log("Failed to download update: %s", type: .notice, error.localizedDescription)
			
			//Show an error
			showError(message: error.localizedDescription)
		}
	}
	
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		DispatchQueue.main.async { [self] in
			if let sheetController = sheetController {
				//Update the progress bar
				sheetController.progressIndicator.doubleValue = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100
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
		} else {
			decisionHandler(.allow)
		}
	}
}
