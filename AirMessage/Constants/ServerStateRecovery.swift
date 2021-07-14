//
//  ServerStateRecovery.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-14.
//

import Foundation

enum ServerStateRecovery {
	case none //This error cannot be recovered by the user
	case retry //The user can retry by clicking a button
	case reauthenticate //The user must reauthenticate
}
