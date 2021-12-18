//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class CommConst {
	static let version: Int32 = 5
	static let subVersion: Int32 = 5
	
	static let defaultFileChunkSize: Int64 = 1024 * 1024 //1 MB
	
	//Timeouts
	static let handshakeTimeout: TimeInterval = 10 //10 seconds
	static let pingTimeout: TimeInterval = 30 //30 seconds
	static let keepAliveMillis: TimeInterval = 30 * 60 //30 minutes
	
	static let maxPacketAllocation = 50 * 1024 * 1024 //50 MB
	
	static let transmissionCheckLength = 32
}

//Net header type
enum NHT: Int32 {
	case close = 0
	case ping = 1
	case pong = 2
	
	case information = 100
	case authentication = 101
	
	case messageUpdate = 200
	case timeRetrieval = 201
	case idRetrieval = 202
	case massRetrieval = 203
	case massRetrievalFile = 204
	case massRetrievalFinish = 205
	case conversationUpdate = 206
	case modifierUpdate = 207
	case attachmentReq = 208
	case attachmentReqConfirm = 209
	case attachmentReqFail = 210
	case idUpdate = 211
	
	case liteConversationRetrieval = 300
	case liteThreadRetrieval = 301
	
	case sendResult = 400
	case sendTextExisting = 401
	case sendTextNew = 402
	case sendFileExisting = 403
	case sendFileNew = 404
	case createChat = 405
	
	case softwareUpdateListing = 500
	case softwareUpdateInstall = 501
	case softwareUpdateError = 502
	
	case faceTimeCreateLink = 600 //Create a new FaceTime link
	case faceTimeOutgoingInitiate = 601 //Initiate a new FaceTime call
	case faceTimeOutgoingHandled = 602 //Notify a client that an outgoing call has been accepted or rejected
	case faceTimeIncomingCallerUpdate = 603 //Notify clients that there is a new incoming call
	case faceTimeIncomingHandle = 604 //Client -> Server: accept or reject the incoming call and return its link
	case faceTimeDisconnect = 605 //Client -> Server: Drop the current call
}

//Net sub-type
enum NSTAuth: Int32 {
	case ok = 0
	case unauthorized = 1
	case badRequest = 2
}

enum NSTSendResult: Int32 {
	case ok = 0
	case scriptError = 1; //Some unknown AppleScript error
	case badRequest = 2 //Invalid data received
	case unauthorized = 3 //System rejected request to send message
	case noConversation = 4 //A valid conversation wasn't found
	case requestTimeout = 5 //File data blocks stopped being received
	case internalError = 6 //An internal error occurred
}

enum NSTAttachmentRequest: Int32 {
	case notFound = 1 //File GUID not found
	case notSaved = 2 //File (on disk) not found
	case unreadable = 3 //No access to file
	case io = 4 //IO error
}

enum NSTCreateChat: Int32 {
	case ok = 0
	case scriptError = 1 //Some unknown AppleScript error
	case badRequest = 2 //Invalid data received
	case unauthorized = 3 //System rejected request to send message
}

enum NSTInitiateFaceTimeCall: Int32 {
	case ok = 0
	case badMembers = 1
	case appleScriptError = 2
}

enum NSTOutgoingFaceTimeCallHandled: Int32 {
	case accepted = 0
	case rejected = 1
	case error = 2
}

enum PushNotificationPayloadType: Int32 {
	case message = 0
	case faceTime = 1
}
