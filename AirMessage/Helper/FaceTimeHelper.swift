//
//  FaceTimeHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-12-03.
//

import Foundation
import Sentry

class FaceTimeHelper {
	private static let intervalPollIncomingCall: TimeInterval = 1
	private static let intervalPollAcceptEntry: TimeInterval = 0.5
	
	private static let incomingCallTimerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".facetime.incominglistener", qos: .utility)
	private static var incomingCallTimer: DispatchSourceTimer? = nil
	private static let lastIncomingCaller = AtomicValue<String?>(initialValue: nil)
	
	private static let outgoingCallTimerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".facetime.outgoinglistener", qos: .utility)
	private static var outgoingCallTimer: DispatchSourceTimer? = nil
	private static let outgoingCallTimerRunning = AtomicBool(initialValue: false)
	private static var outgoingCallListenerArray: [(InitiateCallResult) -> Void] = []
	private static let outgoingCallListenerArrayLock = ReadWriteLock() //Cannot be locked before locking incomingCallTimer
	
	private static let acceptEntryTimerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".facetime.outgoinglistener", qos: .utility)
	private static var acceptEntryTimer: DispatchSourceTimer? = nil
	private static let acceptEntryTimerRunning = AtomicBool(initialValue: false)
	private static var acceptEntryListenerArray: [(Error?) -> Void] = []
	private static let acceptEntryListenerArrayLock = ReadWriteLock() //Cannot be locked before locking incomingCallTimer
	
	private init() {
		
	}
	
	///Gets if FaceTime bridge is supported on this computer
	static var isSupported: Bool = {
		if #available(macOS 12.0, *) {
			//Make sure we're using a supported language, as some UI automation features are language-dependant
			guard let languageCode = Locale.current.languageCode else {
				return false
			}
			return ["en", "fr", "ja"].contains(languageCode)
		} else {
			//Not available on older versions of macOS
			return false
		}
	}()
	
	///Gets if FaceTime bridge is running
	static var isRunning: Bool { incomingCallTimer != nil }
	
	///Gets the current incoming caller, or nil if there is none
	static var currentIncomingCaller: String? { lastIncomingCaller.value }
	
	///Starts the timer that listens for incoming calls
	static func startIncomingCallTimer() {
		//Make sure we're not already running a timer
		guard incomingCallTimer == nil else { return }
		
		//Start a new timer
		let timer = DispatchSource.makeTimerSource(queue: incomingCallTimerQueue)
		timer.schedule(deadline: .now(), repeating: intervalPollIncomingCall)
		timer.setEventHandler(handler: runIncomingCallListener)
		timer.resume()
		incomingCallTimer = timer
		
		LogManager.log("Started listening for FaceTime calls", level: .info)
	}
	
	///Stops the timer that listens for incoming calls
	static func stopIncomingCallTimer() {
		if let timer = incomingCallTimer {
			timer.cancel()
			LogManager.log("Stopped listening for FaceTime calls", level: .info)
		}
		incomingCallTimer = nil
	}
	
	private static func runIncomingCallListener() {
		//Check for incoming calls
		let incomingCaller: String?
		do {
			incomingCaller = try AppleScriptBridge.shared.queryIncomingCall()
		} catch {
			LogManager.log("Failed to query incoming FaceTime call: \(error)", level: .error)
			
			//Ignore -25211 (permission not granted)
			if let error = error as? AppleScriptError, error.code != -25211 {
				SentrySDK.capture(error: error)
			}
			return
		}
		
		guard lastIncomingCaller.with({ value in
			//Ignore if the caller hasn't changed since we last checked
			guard value != incomingCaller else { return false }
			
			//Update the last incoming caller
			value = incomingCaller
			return true
		}) else { return }
		
		if let incomingCaller = incomingCaller {
			LogManager.log("Detected new incoming FaceTime caller: \(incomingCaller)", level: .info)
		} else {
			LogManager.log("No new incoming FaceTime caller", level: .info)
		}
		
		//Notify clients
		ConnectionManager.shared.send(faceTimeCaller: incomingCaller)
		ConnectionManager.shared.sendPushNotification(faceTimeCaller: incomingCaller)
	}
	
	enum InitiateCallResult {
		case accepted(link: String)
		case rejected
		case error(Error)
	}
	
	///Waits for the recipient to accept or reject the active outgoing call. The timer and all listeners are cleaned up after the call is handled.
	static func waitInitiatedCall(onResult listener: @escaping (InitiateCallResult) -> Void) {
		outgoingCallTimerRunning.with { value in
			//Add the listener
			outgoingCallListenerArrayLock.withWriteLock {
				outgoingCallListenerArray.append(listener)
			}
			
			//Ignore if we're already running
			guard !value else { return }
			
			//Set the value to running
			value = true
			
			//Start the timer
			let timer = DispatchSource.makeTimerSource(queue: outgoingCallTimerQueue)
			timer.schedule(deadline: .now(), repeating: intervalPollIncomingCall)
			timer.setEventHandler(handler: runOutgoingCallListener)
			timer.resume()
			outgoingCallTimer = timer
		}
	}
	
	///Waits for a user to ask to enter the call, and lets them in
	static func waitAcceptEntry(onResult listener: @escaping (Error?) -> Void) {
		acceptEntryTimerRunning.with { value in
			//Add the listener
			acceptEntryListenerArrayLock.withWriteLock {
				acceptEntryListenerArray.append(listener)
			}
			
			//Ignore if we're already running
			guard !value else { return }
			
			//Set the value to running
			value = true
			
			//Start the timer
			let timer = DispatchSource.makeTimerSource(queue: acceptEntryTimerQueue)
			timer.schedule(deadline: .now(), repeating: intervalPollAcceptEntry)
			timer.setEventHandler(handler: runAcceptEntryListener)
			timer.resume()
			acceptEntryTimer = timer
		}
	}
	
	private static func runOutgoingCallListener() {
		func cancelAndNotify(result: InitiateCallResult) {
			outgoingCallTimerRunning.with { value in
				outgoingCallListenerArrayLock.withWriteLock {
					//Call the listeners
					for listener in outgoingCallListenerArray {
						listener(result)
					}
					
					//Clear the array
					outgoingCallListenerArray.removeAll()
				}
				
				//Set the timer flag as not running
				value = false
				outgoingCallTimer!.cancel()
				
				//Cancel and invalidate the timer
				outgoingCallTimer = nil
			}
		}
		
		//Check the status of the outgoing call
		let status: AppleScriptBridge.OutgoingCallStatus
		do {
			status = try AppleScriptBridge.shared.queryOutgoingCall()
		} catch {
			LogManager.log("Failed to query outgoing FaceTime call status: \(error)", level: .error)
			SentrySDK.capture(error: error)
			cancelAndNotify(result: .error(error))
			return
		}
		
		if status == .accepted {
			//Get the FaceTime link for the call
			let link: String
			do {
				link = try AppleScriptBridge.shared.getActiveFaceTimeLink()
			} catch {
				//Report the error
				LogManager.log("Failed to get active FaceTime link: \(error)", level: .error)
				SentrySDK.capture(error: error)
				cancelAndNotify(result: .error(error))
				
				//Leave the call
				try? AppleScriptBridge.shared.leaveFaceTimeCall()
				
				return
			}
			
			//Send the link
			cancelAndNotify(result: .accepted(link: link))
		} else if status == .rejected {
			cancelAndNotify(result: .rejected)
		}
	}
	
	private static func runAcceptEntryListener() {
		func cancelAndNotify(error: Error?) {
			acceptEntryTimerRunning.with { value in
				acceptEntryListenerArrayLock.withWriteLock {
					//Call the listeners
					for listener in acceptEntryListenerArray {
						listener(error)
					}
					
					//Clear the array
					acceptEntryListenerArray.removeAll()
				}
				
				//Set the timer flag as not running
				value = false
				acceptEntryTimer!.cancel()
				
				//Cancel and invalidate the timer
				acceptEntryTimer = nil
			}
		}
		
		let accepted: Bool
		do {
			accepted = try AppleScriptBridge.shared.acceptFaceTimeEntry()
		} catch {
			//Report the error
			cancelAndNotify(error: error)
			
			//Leave the call
			try? AppleScriptBridge.shared.leaveFaceTimeCall()
			
			return
		}
		
		if accepted {
			//Finish
			cancelAndNotify(error: nil)
		}
	}
}
