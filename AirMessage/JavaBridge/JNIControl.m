//
//  JNIControl.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-08.
//

#import "JNIControl.h"
#import "JVM.h"
#import "JVMHelper.h"
#import "AirMessage-Swift.h"

#define CLASSNAME "me/tagavari/airmessageserver/jni/JNIControl"

void jniStartServer(void) {
	JNIEnv *env = getJNIEnv();
	jclass class = (*env)->FindClass(env, CLASSNAME);
	jmethodID methodID = (*env)->GetStaticMethodID(env, class, "onStartServer", "()V");
	(*env)->CallStaticVoidMethod(env, class, methodID);
	
	handleException(env);
}

void jniStopServer(void) {
	JNIEnv *env = getJNIEnv();
	jclass class = (*env)->FindClass(env, CLASSNAME);
	jmethodID methodID = (*env)->GetStaticMethodID(env, class, "onStopServer", "()V");
	(*env)->CallStaticVoidMethod(env, class, methodID);
	
	handleException(env);
}

NSMutableArray<ClientRegistration *>* jniGetClients(void) {
    JNIEnv *env = getJNIEnv();
    jclass class = (*env)->FindClass(env, CLASSNAME);
    jmethodID methodID = (*env)->GetStaticMethodID(env, class, "getClients", "()[Lme/tagavari/airmessageserver/jni/record/JNIClientRegistration;");
    jobjectArray javaClientArray = (*env)->CallObjectMethod(env, class, methodID);

	handleException(env);

	jsize arrayLength = (*env)->GetArrayLength(env, javaClientArray);
	NSMutableArray<ClientRegistration *>* nsArray = [NSMutableArray arrayWithCapacity:(NSUInteger) arrayLength];
	for(int i = 0; i < arrayLength; i++) {
		jobject javaClient = (*env)->GetObjectArrayElement(env, javaClientArray, i);

		jclass javaClientClass = (*env)->GetObjectClass(env, javaClient);
		jmethodID mInstallationID = (*env)->GetMethodID(env, javaClientClass, "installationID", "()Ljava/lang/String;");
		jmethodID mClientName = (*env)->GetMethodID(env, javaClientClass, "clientName", "()Ljava/lang/String;");
		jmethodID mPlatformID = (*env)->GetMethodID(env, javaClientClass, "platformID", "()Ljava/lang/String;");

		[nsArray addObject:[[ClientRegistration alloc]
				initWithInstallationID:javaStringToNSString(env, (*env)->CallObjectMethod(env, javaClient, mInstallationID))
							clientName:javaStringToNSString(env, (*env)->CallObjectMethod(env, javaClient, mClientName))
							platformID:javaStringToNSString(env, (*env)->CallObjectMethod(env, javaClient, mPlatformID))]];
	}

	return nsArray;
}
