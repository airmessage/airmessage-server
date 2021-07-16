//
//  ServerState.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-04.
//

import Foundation

fileprivate let typeStatuses: [ServerState] = [.setup, .starting, .connecting, .running, .stopped]

fileprivate let typeRequiresReauth: [ServerState] = [.errorConnValidation, .errorConnToken, .errorConnAccountConflict]

enum ServerState: Int {
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
	
	var description: String {
		switch(self) {
			case .setup:
				return NSLocalizedString("message.status.setup", comment: "")
			case .starting:
				return NSLocalizedString("message.status.starting", comment: "")
			case .connecting:
				return NSLocalizedString("message.status.connecting", comment: "")
			case .running:
				return NSLocalizedString("message.status.running", comment: "")
			case .stopped:
				return NSLocalizedString("message.status.stopped", comment: "")
			case .errorDatabase:
				return NSLocalizedString("message.status.error.database", comment: "")
			case .errorInternal:
				return NSLocalizedString("message.status.error.internal", comment: "")
			case .errorExternal:
				return NSLocalizedString("message.status.error.external", comment: "")
			case .errorInternet:
				return NSLocalizedString("message.status.error.internet", comment: "")
			case .errorTCPPort:
				return NSLocalizedString("message.status.error.port", comment: "")
			case .errorConnBadRequest:
				return NSLocalizedString("message.status.error.bad_request", comment: "")
			case .errorConnOutdated:
				return NSLocalizedString("message.status.error.outdated", comment: "")
			case .errorConnValidation:
				return NSLocalizedString("message.status.error.account_validation", comment: "")
			case .errorConnToken:
				return NSLocalizedString("message.status.error.token_refresh", comment: "")
			case .errorConnActivation:
				return NSLocalizedString("message.status.error.no_activation", comment: "")
			case .errorConnAccountConflict:
				return NSLocalizedString("message.status.error.account_conflict", comment: "")
		}
	}
	
	var isError: Bool {
		!typeStatuses.contains(self)
	}
	
	var recoveryType: ServerStateRecovery {
		if typeRequiresReauth.contains(self) {
			return .reauthenticate
		} else {
			return .retry
		}
	}
}
