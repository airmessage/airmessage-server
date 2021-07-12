//
// Created by Cole Feuer on 2021-07-04.
//

#import "JNIUserInterface.h"
#import "JVM.h"

#define CLASSNAME "me/tagavari/airmessageserver/jni/JNIUserInterface"

void updateUIState(JNIEnv *env, jclass thisClass, jint state) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"updateUIState" object:nil userInfo:@{@"state": @(state)}];
    });
}

void updateConnectionCount(JNIEnv *env, jclass thisClass, jint count) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:@"updateConnectionCount" object:nil userInfo:@{@"count": @(count)}];
	});
}

void registerJNIUserInterface(JNIEnv *env) {
    JNINativeMethod methods[] = {
		{"updateUIState", "(I)V", updateUIState},
		{"updateConnectionCount", "(I)V", updateConnectionCount},
    };
    (*env)->RegisterNatives(env, (*env)->FindClass(env, CLASSNAME), methods, sizeof(methods) / sizeof(methods[0]));
}
