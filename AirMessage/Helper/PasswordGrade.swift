//
//  PasswordGrade.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-01-04.
//

import Foundation

func calculatePasswordStrength(_ password: String) -> Int {
	var score = 0
	
	//Up to 6 points for a length of 10
	score += min(Int(Double(password.count) / 10.0 * 6.0), 6)
	
	//1 point for a digit
	if password.range(of: "(?=.*[0-9]).*", options: .regularExpression) != nil {
		score += 1
	}
	
	//1 point for a lowercase letter
	if password.range(of: "(?=.*[a-z]).*", options: .regularExpression) != nil {
		score += 1
	}
	
	//1 point for an uppercase letter
	if password.range(of: "(?=.*[A-Z]).*", options: .regularExpression) != nil {
		score += 1
	}
	
	//1 point for a special character
	if password.range(of: "(?=.*[~!@#$%^&*()_-]).*", options: .regularExpression) != nil {
		score += 1
	}
	
	return score
}

func getPasswordStrengthLabel(_ value: Int) -> String {
	switch value {
	case 0..<5:
		return NSLocalizedString("passwordstrength.level1", comment: "")
	case 5..<7:
		return NSLocalizedString("passwordstrength.level2", comment: "")
	case 7..<9:
		return NSLocalizedString("passwordstrength.level3", comment: "")
	default:
		return NSLocalizedString("passwordstrength.level4", comment: "")
	}
}
