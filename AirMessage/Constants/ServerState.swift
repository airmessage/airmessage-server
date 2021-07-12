//
// Created by Cole Feuer on 2021-07-04.
//

import Foundation

enum ServerState: Int {
	case initializing = 0
	case setup = 1
	case starting = 2
	case connecting = 3
	case running = 4
	case stopped = 5
	
	case errorDatabase = 100
	case errorInternal = 101
	case errorExternal = 102
	case errorInternet = 103
	
	case errorTCPPort = 200
	
	case errorConnBadRequest = 300
	case errorConnOutdated = 301
	case errorConnValidation = 302
	case errorConnToken = 303
	case errorConnActivation = 304
	case errorConnAccountConflict = 305
}
