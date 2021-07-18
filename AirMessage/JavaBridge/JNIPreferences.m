//
//  JNIPreferences.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-04.
//

#import "JNIPreferences.h"
#import "AirMessage-Swift.h"

jint getServerPort(JNIEnv *env, jclass thisClass) {
	return PreferencesManager.getShared.serverPort;
}

jint getAccountType(JNIEnv *env, jclass thisClass) {
	return PreferencesManager.getShared.accountType;
}

jstring getPassword(JNIEnv *env, jclass thisClass) {
	NSString *password = PreferencesManager.getShared.password;
	return (*env)->NewStringUTF(env, [password UTF8String]);
}

jstring getInstallationID(JNIEnv *env, jclass thisClass) {
	NSString *installationID = PreferencesManager.getShared.installationID;
	return (*env)->NewStringUTF(env, [installationID UTF8String]);
}

jstring getFirebaseIDToken(JNIEnv *env, jclass thisClass) {
	NSError* err = nil;
	NSString *idToken = [FirebaseAuthHelper.getShared getIDTokenAndReturnError:&err];
	
	if(err != nil) {
		NSLog(@"%@", err.description);
		return NULL;
	}
	return (*env)->NewStringUTF(env, [idToken UTF8String]);
}

void registerJNIPreferences(JNIEnv *env) {
    JNINativeMethod methods[] = {
		{"getServerPort", "()I", getServerPort},
		{"getAccountType", "()I", getAccountType},
		{"getPassword", "()Ljava/lang/String;", getPassword},
		{"getInstallationID", "()Ljava/lang/String;", getInstallationID},
		{"getFirebaseIDToken", "()Ljava/lang/String;", getFirebaseIDToken},
	};
    (*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIPreferences"), methods, sizeof(methods) / sizeof(methods[0]));
}
