//
//  DBFetchGrouping.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-15.
//

import Foundation

/**
 A result for database operations that return conversation items and loose modifiers
 */
struct DBFetchGrouping {
	let conversationItems: [ConversationItem]
	let looseModifiers: [ModifierInfo]
	
	var destructured: ([ConversationItem], [ModifierInfo]) {
		return (conversationItems, looseModifiers)
	}
}
