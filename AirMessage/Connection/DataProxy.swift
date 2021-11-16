//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

protocol DataProxy: AnyObject {
	/**
	 Sets the delegate of this proxy for updates
	 */
	var delegate: DataProxyDelegate? { get set }
	
	/**
	 Gets the non-localized name of this proxy
	 */
	var name: String { get }
	
	/**
	 Gets whether this protocol requires clients to authenticate with a password
	 */
	var requiresAuthentication: Bool { get }
	
	/**
	 Gets whether this protocol requires the server to actively maintain connections
	 */
	var requiresPersistence: Bool { get }
	
	/**
	 Gets whether this protocol supports push notifications
	 */
	var supportsPushNotifications: Bool { get }
	
	/**
	 Gets a list of connected clients
	 */
	var connections: Set<ClientConnection> { get }
	var connectionsLock: NSLock { get }
	
	/**
	 Starts this server, allowing it to accept incoming connections
	 */
	func startServer()
	
	/**
	 Stops the server, disconnecting all connected clients
	 */
	func stopServer()
	
	/**
	 Sends a message to the specified client
	 - Parameters:
	   - data: The data to send
	   - client: The client to send the data to, or nil to broadcast
	   - encrypt: Whether or not to encrypt this data
	   - onSent: A callback invoked when the message is sent, or nil to ignore
	 */
	func send(message data: Data, to client: ClientConnection?, encrypt: Bool, onSent: (() -> Void)?)
	
	/**
	 Sends a push notification to notify all disconnected clients of new information
	 - Parameters:
	   - data: The data to send
	   - version: The version number to attach to this data
	 */
	func send(pushNotification data: Data, version: Int)
	
	/**
	 Disconnects a client from this server
	 */
	func disconnect(client: ClientConnection)
}
