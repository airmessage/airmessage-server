//
//  ClientList.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-31.
//

import Foundation
import AppKit

class ClientListViewController: NSViewController {
    //Keep in memory on older versions of OS X
    private static var clientListWindowController: NSWindowController!
    
	private static let cellID = NSUserInterfaceItemIdentifier(rawValue: "DeviceTableCell")
	
	@IBOutlet weak var tableView: NSTableView!
	
	private var clients: [ClientConnection.Registration]!
    
    static func open() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "ClientList") as! NSWindowController
        windowController.showWindow(nil)
        clientListWindowController = windowController
    }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		//Load data
		clients = ConnectionManager.shared.connections
			.map { connSet in
				connSet.sorted { $0.id > $1.id }
				.compactMap { $0.registration }
			} ?? []
		
		//Set table delegate
		tableView.delegate = self
		tableView.dataSource = self
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.client_log", comment: "")
		
		//Focus app
		NSApp.activate(ignoringOtherApps: true)
	}
}

extension ClientListViewController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		clients.count
	}
}

extension ClientListViewController: NSTableViewDelegate {
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.makeView(withIdentifier: ClientListViewController.cellID, owner: self) as! ClientTableCellView
		
		guard row < clients.count else {
			return nil
		}
		let client = clients[row]
		
		let image: NSImage
		switch client.platformID {
			case "android":
				image = NSImage(named: "Android")!
			case "windows":
				image = NSImage(named: "Windows")!
			case "chrome":
				image = NSImage(named: "BrowserChrome")!
			case "firefox":
				image = NSImage(named: "BrowserFirefox")!
			case "edge":
				image = NSImage(named: "BrowserEdge")!
			case "opera":
				image = NSImage(named: "BrowserOpera")!
			case "samsunginternet":
				image = NSImage(named: "BrowserSamsung")!
			case "safari":
				image = NSImage(named: "BrowserSafari")!
			default:
				image = NSImage(named: NSImage.networkName)!
		}
		
		cell.icon.image = image
		cell.title.stringValue = client.clientName
		cell.subtitle.stringValue = NSLocalizedString("label.currently_connected", comment: "")
		
		return cell
	}
}
