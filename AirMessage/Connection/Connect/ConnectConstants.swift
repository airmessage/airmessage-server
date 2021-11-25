//
//  ConnectConstants.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-23.
//

import Foundation

class ConnectConstants {
	//AirMessage Connect communications version
	static let commVer = 1
	
	//Timeout for handshake from server
	static let handshakeTimeout: TimeInterval = 8
}

enum ConnectNHT: Int32 {
	//Shared Net header types
	/*
	 * The connected device has been connected successfully
	 */
	case connectionOK = 0
	
	//Client-only net header types
	
	/*
	 * Proxy the message to the server (client -> connect)
	 *
	 * payload - data
	 */
	case clientProxy = 100
	
	/*
	 * Add an item to the list of FCM tokens (client -> connect)
	 *
	 * string - registration token
	 */
	case clientAddFCMToken = 110
	
	/*
	 * Remove an item from the list of FCM tokens (client -> connect)
	 *
	 * string - registration token
	 */
	case clientRemoveFCMToken = 111
	
	//Server-only net header types
	
	/*
	 * Notify a new client connection (connect -> server)
	 *
	 * int - connection ID
	 */
	case serverOpen = 200
	
	/*
	 * Close a connected client (server -> connect)
	 * Notify a closed connection (connect -> server)
	 *
	 * int - connection ID
	 */
	case serverClose = 201
	
	/*
	 * Proxy the message to the client (server -> connect)
	 * Receive data from a connected client (connect -> server)
	 *
	 * int - connection ID
	 * payload - data
	 */
	case serverProxy = 210
	
	/*
	 * Proxy the message to all connected clients (server -> connect)
	 *
	 * payload - data
	 */
	case serverProxyBroadcast = 211
	
	/*
	 * Notify offline clients of a new message
	 */
	case serverNotifyPush = 212
}

enum ConnectCloseCode: UInt16 {
	case incompatibleProtocol = 4000 //No protocol version matching the one requested
	case noGroup = 4001 //There is no active group with a matching ID
	case noCapacity = 4002 //The client's group is at capacity
	case accountValidation = 4003 //This account couldn't be validated
	case serverTokenRefresh = 4004 //The server's provided installation ID is out of date; log in again to re-link this device
	case noActivation = 4005 //This user's account is not activated
	case otherLocation = 4006 //Logged in from another location
}
