//
//  ClientList.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-31.
//

import Foundation
import AppKit

class ClientListViewController: NSViewController {
	private static let cellID = NSUserInterfaceItemIdentifier(rawValue: "DeviceTableCell")
	
	@IBOutlet weak var tableView: NSTableView!
	
	private var clients: [ClientConnection.Registration]!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		//Load data
		//clients = (jniGetClients() as! [ClientRegistration])
		clients = []
		
		//Set table delegate
		tableView.delegate = self
		tableView.dataSource = self
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
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
		cell.subtitle.stringValue = "Currently connected"
		
		return cell
	}
}
