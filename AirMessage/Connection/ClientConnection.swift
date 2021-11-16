//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class ClientConnection {
	var id: Int32
	
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
	var isConnected: Bool = true
	
	init(id: Int32) {
		self.id = id
	}
	
	deinit {
		//Ensure timers are cleaned up
		cancelAllTimers()
	}
	
	//MARK: Timers
	
	enum TimerType {
		case handshakeExpiry
		case pingExpiry
	}
	
	struct RunningTimer {
		let timer: Timer
		let callback: (ClientConnection) -> Void
	}
	
	private var timerDict: [TimerType: RunningTimer] = [:]
	
	/**
	 Cancels all pending expiry timers
	 */
	func cancelAllTimers() {
		for (_, runningTimer) in timerDict {
			runningTimer.timer.invalidate()
		}
		timerDict.removeAll()
	}
	
	/**
	 Cancels the expiry timer of the specified type
	 */
	func cancelTimer(ofType type: TimerType) {
		timerDict[type]?.timer.invalidate()
		timerDict[type] = nil
	}
	
	/**
	 Schedules a timer of the specified type after interval to run the callback
	 If a timer was previously scheduled of this type, that timer is cancelled and replaced with this one
	 */
	func startTimer(ofType type: TimerType, interval: TimeInterval, callback: @escaping (ClientConnection) -> Void) {
		//Cancel existing timers
		cancelTimer(ofType: type)
		
		//Create and start the timer
		let timer = Timer(timeInterval: interval, target: self, selector: #selector(onTimerExpire), userInfo: type, repeats: false)
		RunLoop.main.add(timer, forMode: .common)
		timerDict[type] = RunningTimer(timer: timer, callback: callback)
	}
	
	@objc private func onTimerExpire(timer: Timer) {
		//Invoke the callback of the specified type
		let type = timer.userInfo as! TimerType
		timerDict[type]?.callback(self)
		timerDict[type] = nil
	}
}

//MARK: Hashable

extension ClientConnection: Hashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
	
	static func ==(lhs: ClientConnection, rhs: ClientConnection) -> Bool {
		lhs.id == lhs.id
	}
}
