//
//  JNIMessage.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

#import <Foundation/Foundation.h>

#import "JNIPreferences.h"
#import "JVMHelper.h"
#import "AirMessage-Swift.h"

const char *classNameExceptionAppleScript = "me/tagavari/airmessageserver/jni/exception/JNIAppleScriptException";
const char *classNameExceptionNotSupported = "me/tagavari/airmessageserver/jni/exception/JNINotSupportedException";

jint throwError(JNIEnv *env, NSError *error) {
	if(error.domain == AppleScriptExecutionError.errorDomain) {
		jclass errorClass = (*env)->FindClass(env, classNameExceptionAppleScript);
		jmethodID errorConstructor = (*env)->GetMethodID(env, errorClass, "<init>", "(Ljava/lang/String;I)V");
		jobject errorObject = (*env)->NewObject(env, errorClass, errorConstructor, error.localizedDescription.UTF8String, error.code);

		return (*env)->Throw(env, errorObject);
	} else if(error.domain == AppleScriptSupportError.errorDomain) {
		jclass errorClass = (*env)->FindClass(env, classNameExceptionNotSupported);
		jmethodID errorConstructor = (*env)->GetMethodID(env, errorClass, "<init>", "(Ljava/lang/String;)V");
		jobject errorObject = (*env)->NewObject(env, errorClass, errorConstructor, ((NSString*) error.userInfo[AppleScriptSupportError .userInfoVersion]).UTF8String);

		return (*env)->Throw(env, errorObject);
	} else {
		return throwNSError(env, error);
	}
}

jstring createChat(JNIEnv *env, jclass thisClass, jobjectArray addresses, jstring service) {
    NSError* error = nil;
	NSString *chatGUID = [MessageManager
						  createChatWithAddresses:javaStringArrayToNSArray(env, addresses)
						  service:javaStringToNSString(env, service)
                          error:&error];
	
	//Return result
	if(error != nil) {
		throwError(env, error);
		return NULL;
	} else {
		return (*env)->NewStringUTF(env, [chatGUID UTF8String]);
	}
}

void sendExistingMessage(JNIEnv *env, jclass thisClass, jstring chatGUID, jstring message) {
	NSError* error = nil;
	[MessageManager
			sendWithMessage:javaStringToNSString(env, message)
			toExistingChat:javaStringToNSString(env, chatGUID)
			error:&error];

	if(error != nil) {
		throwError(env, error);
	}
}

void sendNewMessage(JNIEnv *env, jclass thisClass, jobjectArray addresses, jstring service, jstring message) {
	NSError* error = nil;
	[MessageManager
			sendWithMessage:javaStringToNSString(env, message)
			toNewChat:javaStringArrayToNSArray(env, addresses)
			onService:javaStringToNSString(env, service)
			error:&error];

	if(error != nil) {
		throwError(env, error);
	}
}

void sendExistingFile(JNIEnv *env, jclass thisClass, jstring chatGUID, jstring filePath) {
	NSError* error = nil;
	[MessageManager
			sendWithFile:[NSURL fileURLWithPath:javaStringToNSString(env, filePath) isDirectory:NO]
			toExistingChat:javaStringToNSString(env, chatGUID)
			error:&error];

	if(error != nil) {
		throwError(env, error);
	}
}

void sendNewFile(JNIEnv *env, jclass thisClass, jobjectArray addresses, jstring service, jstring filePath) {
	NSError* error = nil;
	[MessageManager
			sendWithFile:[NSURL fileURLWithPath:javaStringToNSString(env, filePath) isDirectory:NO]
			toNewChat:javaStringArrayToNSArray(env, addresses)
			onService:javaStringToNSString(env, service)
			error:&error];

	if(error != nil) {
		throwError(env, error);
	}
}

void registerJNIMessage(JNIEnv *env) {
	JNINativeMethod methods[] = {
		{"createChat", "([Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", createChat},
		{"sendExistingMessage", "(Ljava/lang/String;Ljava/lang/String;)V", sendExistingMessage},
		{"sendNewMessage", "([Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", sendNewMessage},
		{"sendExistingFile", "(Ljava/lang/String;Ljava/lang/String;)V", sendExistingFile},
		{"sendNewFile", "([Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", sendNewFile},
	};
	(*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIMessage"), methods, sizeof(methods) / sizeof(methods[0]));
}
