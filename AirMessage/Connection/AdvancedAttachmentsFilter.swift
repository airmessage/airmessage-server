//
//  AdvancedAttachmentsFilter.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-20.
//

import Foundation

struct AdvancedAttachmentsFilter {
	let timeSince: Int64?
	let maxSize: Int64?
	
	let whitelist: [String] //If it's on the whitelist, download it
	let blacklist: [String] //If it's on the blacklist, skip it
	let downloadExceptions: Bool //If it's on neither list, download if if this value is true
	
	/**
	 Checks if the attachment passes this filter
	 */
	func apply(to attachment: AttachmentInfo, ofDate: Int64) -> Bool {
		//Check time since
		if let timeSince = timeSince,
		   ofDate < timeSince {
			return false
		}
		
		//Check max size
		if let maxSize = maxSize, attachment.size > maxSize {
			return false
		}
		
		//Check content type
		guard let attachmentType = attachment.type else {
			return false
		}
		
		if whitelist.contains(where: { type in compareMIMETypes(type, attachmentType) }) {
			return true
		}
		
		if blacklist.contains(where: { type in compareMIMETypes(type, attachmentType) }) {
			return false
		}
		
		return downloadExceptions
	}
}
