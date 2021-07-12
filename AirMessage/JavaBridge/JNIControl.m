//
//  JNIControl.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-08.
//

#import "JNIControl.h"
#import "JVM.h"

#define CLASSNAME "me/tagavari/airmessageserver/jni/JNIControl"

void jniStartServer() {
	JNIEnv *env = getJNIEnv();
	jclass class = (*env)->FindClass(env, CLASSNAME);
	jmethodID methodID = (*env)->GetStaticMethodID(env, class, "onStartServer", "()V");
	(*env)->CallStaticVoidMethod(env, class, methodID);
}
