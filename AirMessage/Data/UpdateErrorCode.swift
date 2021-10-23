//
// Created by Cole Feuer on 2021-10-23.
//

import Foundation

@objc enum UpdateErrorCode: Int {
	case download = 0
	case badPackage = 1
	case internalError = 2
}
