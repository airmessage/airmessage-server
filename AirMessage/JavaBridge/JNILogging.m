//
//  JNILogging.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

#import <Foundation/Foundation.h>
#import "JNILogging.h"
#import "JVMHelper.h"
#import "AirMessage-Swift.h"

void javaLog(JNIEnv *env, jclass thisClass, jint type, jstring message) {
	NSString *logString = javaStringToNSString(env, message);
	[LogManager.shared javaLog:logString type:type];
}

void registerJNILogging(JNIEnv *env) {
	JNINativeMethod methods[] = {
		{"log", "(ILjava/lang/String;)V", javaLog},
	};
	(*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNILogging"), methods, sizeof(methods) / sizeof(methods[0]));
}
