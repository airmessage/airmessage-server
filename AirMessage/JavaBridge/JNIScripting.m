//
// Created by Cole Feuer on 2021-07-10.
//

#import "JNIScripting.h"
#import "AirMessage-Swift.h"

bool isAutomationAllowed(JNIEnv *env) {
	return AppleScriptBridge.shared.checkPermissionsMessages;
}
