//
//  ContentTypeHelper.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-20.
//

import Foundation

/**
 Runs a simple comparison of 2 MIME types, returning if they overlap
 */
func compareMIMETypes(_ value1: String, _ value2: String) -> Bool {
	//Handle case where either type is a complete wildcard
	if value1 == "*/*" || value2 == "*/*" {
		return true
	}
	
	//Split MIME types into type and subtype
	let split1 = value1.split(separator: "/", maxSplits: 2)
	let split2 = value2.split(separator: "/", maxSplits: 2)
	
	//Make sure that we have 2 splits
	guard split1.count == 2 && split2.count == 2 else {
		return false
	}
	
	//If the subtype of either value is a wildcard, compare their main types
	if split1[1] == "*" || split2[1] == "*" {
		return split1[0] == split2[0]
	}
	
	//Just do a direct comparison
	return value1 == value2
}
