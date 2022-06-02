//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class ClientConnection {
	let id: Int32
	
	//Overridable by subclasses
	var readableID: String { String(id) }
	
	struct Registration {
		/**
		 * The installation ID of this instance
		 * Used for blocking multiple connections from the same client
		 */
		let installationID: String
		
		/**
		 * A human-readable name for this client
		 * Used when displaying connected clients to the user
		 * Examples:
		 * - Samsung Galaxy S20
		 * - Firefox 75
		 */
		let clientName: String
		
		/**
		 * The ID of the platform this device is running on
		 * Examples:
		 * - "android" (AirMessage for Android)
		 * - "google chrome" (AirMessage for web)
		 * - "windows" (AirMessage for Windows)
		 */
		let platformID: String
	}
	//Registration information for this client, once it's completed its handshake with the server
	var registration: Registration?
	
	//The current awaited transmission check for this client
	var transmissionCheck: Data?
	
	//Whether this client is connected. Set to false when the client disconnects.
	var isConnected = AtomicBool(initialValue: true)
	
	init(id: Int32) {
		self.id = id
	}
	
	deinit {
		//Ensure timers are cleaned up
		assert(timerDict.isEmpty, "Client connection was deinitialized with active timers")
	}
	
	//MARK: Timers
	
	enum TimerType {
		case handshakeExpiry
		case pingExpiry
	}
	
	private var timerDict: [TimerType: DispatchSourceTimer] = [:]
	
	/**
	 Cancels all pending expiry timers
	 */
	func cancelAllTimers() {
		for (_, runningTimer) in timerDict {
			runningTimer.cancel()
		}
		timerDict.removeAll()
	}
	
	/**
	 Cancels the expiry timer of the specified type
	 */
	func cancelTimer(ofType type: TimerType, queue: DispatchQueue) {
		//Make sure we're on the provided dispatch queue
		assertDispatchQueue(queue)
		
		timerDict[type]?.cancel()
		timerDict[type] = nil
	}
	
	/**
	 Schedules a timer of the specified type after interval to run the callback
	 If a timer was previously scheduled of this type, that timer is cancelled and replaced with this one
	 */
	func startTimer(ofType type: TimerType, interval: TimeInterval, queue: DispatchQueue, callback: @escaping (ClientConnection) -> Void) {
		//Make sure we're on the provided dispatch queue
		assertDispatchQueue(queue)
		
		//Cancel existing timers
		cancelTimer(ofType: type, queue: queue)
		
		//Create and start the timer
		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now() + interval, repeating: .never)
		timer.setEventHandler { [weak self] in
			//Make sure we're still on the same queue
			assertDispatchQueue(queue)
			
			//Check our reference to self
			guard let self = self else {
				return
			}
			
			//Invoke the callback
			callback(self)
			
			//Remove this timer
			self.timerDict[type] = nil
		}
		timer.resume()
		timerDict[type] = timer
	}
}
