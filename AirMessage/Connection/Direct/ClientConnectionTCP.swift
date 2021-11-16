//
// Created by Cole Feuer on 2021-11-13.
//

import Foundation

class ClientConnectionTCP: ClientConnection {
	//Constants
	private static let headerLen = MemoryLayout<Int32>.size + MemoryLayout<Bool>.size
	
	//Parameters
	let handle: FileHandle
	weak var delegate: ClientConnectionTCPDelegate?
	
	//State
	private var isRunning = AtomicBool()
	
	init(id: Int32, handle: FileHandle, delegate: ClientConnectionTCPDelegate? = nil) {
		self.handle = handle
		self.delegate = delegate
		super.init(id: id)
	}
	
	func start(on queue: DispatchQueue) {
		//Return if we're already running
		guard !isRunning.with({ value in
			//If we're not running, change the property to running
			if !value {
				value = true
			}
			return value
		}) else { return }
		
		//Start reader task
		queue.async { [weak self] in
			do {
				while self?.isRunning.value ?? false {
					guard let self = self else { break }
					
					//Read packet header
					let packetHeader = try ClientConnectionTCP.read(handle: self.handle, exactCount: ClientConnectionTCP.headerLen)
					let (contentLen, isEncrypted) = packetHeader.withUnsafeBytes { ptr in
						(
								ptr.load(fromByteOffset: 0, as: Int32.self),
								ptr.load(fromByteOffset: MemoryLayout<Int32>.size, as: Bool.self)
						)
					}
					
					//Check if the content length is greater than the maximum packet allocation
					guard contentLen < CommConst.maxPacketAllocation else {
						//Log and disconnect
						LogManager.shared.log("Rejecting large packet (size %{public})", type: .notice, contentLen)
						
						self.stop(cleanup: true)
						break
					}
					
					//Read the content
					let packetContent = try ClientConnectionTCP.read(handle: self.handle, exactCount: Int(contentLen))
					self.delegate?.clientConnectionTCP(self, didReceive: packetContent, isEncrypted: isEncrypted)
				}
			} catch {
				//Log and disconnect
				LogManager.shared.log("An error occurred while reading client data: %{public}", type: .notice, error.localizedDescription)
				self?.stop(cleanup: false)
			}
		}
	}
	
	func stop(cleanup: Bool) {
		//Return if we're not running
		guard isRunning.with({ value in
			//If we're running, change the property to not running
			if value {
				value = false
			}
			return value
		}) else { return }
		
		//Update the connected property
		isConnected.value = false
		
		//Close the file handle
		do {
			try handle.closeCompat()
		} catch {
			LogManager.shared.log("An error occurred while closing a client handle: %{public}", type: .notice, error.localizedDescription)
		}
		
		//Call the delegate
		delegate?.clientConnectionTCPDidInvalidate(self)
	}
	
	/**
	 Writes the provided data to the client
	 - Parameters:
	   - data: The data to write
	   - isEncrypted: Whether to mark the data as encrypted
	 */
	@discardableResult
	func write(data: Data, isEncrypted: Bool) -> Bool {
		//Create the packet structure
		var output = Data(capacity: MemoryLayout<Int32>.size + MemoryLayout<Bool>.size + data.count)
		withUnsafeBytes(of: data.count.bigEndian) { output.append(contentsOf: $0) }
		output.append(isEncrypted ? 1 : 0)
		output.append(data)
		
		//Write the packet
		do {
			try handle.writeCompat(contentsOf: output)
		} catch {
			return false
		}
		
		return true
	}
	
	deinit {
		stop(cleanup: false)
	}
	
	enum ReadError: Error {
		case eof
		case readError
	}
	
	/**
	 Reads from a `FileHandle`
	 - Parameters:
	   - handle: The handle to read from
	   - count: The maximum amount of bytes to read
	 - Returns: The read data
	 - Throws: A read error if the file handle could not be read
	 */
	private static func read(handle: FileHandle, upToCount count: Int) throws -> Data {
		let data: Data
		do {
			data = try handle.readCompat(upToCount: count)
		} catch {
			throw ReadError.readError
		}
		
		if data.isEmpty {
			throw ReadError.eof
		}
		
		return data
	}
	
	/**
	 Reads an exact amount of bytes from a `FileHandle`
	 - Parameters:
	   - handle: The handle to read from
	   - count: The amount of bytes to read
	 - Returns: The read data
	 - Throws: A read error if the file handle could not be read
	 */
	private static func read(handle: FileHandle, exactCount count: Int) throws -> Data {
		var exactData = Data(capacity: count)
		
		repeat {
			let data = try read(handle: handle, upToCount: exactData.count - count)
			exactData.append(data)
		} while exactData.count < count
		
		return exactData
	}
}

protocol ClientConnectionTCPDelegate: AnyObject {
	/**
	 Tells the delegate that this connection received an incoming message
	 - Parameters:
	   - client: The client calling this method
	   - data: The data received from the client
	   - isEncrypted: Whether the received data is encrypted
	 */
	func clientConnectionTCP(_ client: ClientConnectionTCP, didReceive data: Data, isEncrypted: Bool)
	
	/**
	 Tells the delegate that this connection encountered an error, and must be closed
	 - Parameters:
	   - client: The client calling this method
	 */
	func clientConnectionTCPDidInvalidate(_ client: ClientConnectionTCP)
}
