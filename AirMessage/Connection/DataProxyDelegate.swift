//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

protocol DataProxyDelegate: AnyObject {
	typealias C = ClientConnection
	
	/**
	 Called when the proxy is started successfully
	 */
	func dataProxyDidStart(_ dataProxy: DataProxy)
	
	/**
	 Called when the proxy is stopped
	 If isRecoverable is true, the proxy will continue trying to reconnect in the background,
	 and call `dataProxyDidStart` when the connection is resolved.
	 */
	func dataProxy(_ dataProxy: DataProxy, didStopWithState state: ServerState, isRecoverable: Bool)
	
	/**
	 Called when a new client is connected
	 */
	func dataProxy(_ dataProxy: DataProxy, didConnectClient client: C, totalCount: Int)
	
	/**
	 Called when a client is disconnected
	 */
	func dataProxy(_ dataProxy: DataProxy, didDisconnectClient client: C, totalCount: Int)
	
	/**
	 Called when a message is received
	 - Parameters:
	   - data: The message data
	   - client: The client that sent the message
	   - wasEncrypted: True if this message was encrypted during transit (and probably contains sensitive content)
	 */
	func dataProxy(_ dataProxy: DataProxy, didReceive data: Data, from client: C, wasEncrypted: Bool)
}
