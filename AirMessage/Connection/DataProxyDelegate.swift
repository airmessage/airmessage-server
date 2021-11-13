//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

protocol DataProxyDelegate: AnyObject {
	typealias C = ClientConnection
	
	/**
	 Called when the proxy is started successfully
	 */
	func dataProxyDidStart()
	
	/**
	 Called when the proxy is paused
	 This happens when a temporary, automatically recoverable error occurs in the proxy,
	 such as a dropped connection. No user input is required to solve these problems,
	 but this updates the UI so the user at least knows what's going on.
	 *
	 This method cannot be called while the server is in setup mode, and should instead
	 redirect to `onStop`
	 */
	func dataProxy(didPauseWithState: ServerState)
	
	/**
	 Called when the proxy is stopped
	 (either as directed or due to an exception)
	 */
	func dataProxy(didStopWithState: ServerState)
	
	/**
	 Called when a new client is connected
	 */
	func dataProxy(didConnectClient: C)
	
	/**
	 Called when a client is disconnected
	 */
	func dataProxy(didDisconnectClient: C)
	
	/**
	 Called when a message is received
	 - Parameters:
	   - data: The message data
	   - client: The client that sent the message
	   - wasEncrypted: True if this message was encrypted during transit (and probably contains sensitive content)
	 */
	func dataProxy(didReceive data: Data, from client: C, wasEncrypted: Bool)
}