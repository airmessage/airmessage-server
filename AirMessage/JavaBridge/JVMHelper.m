//
//  JVMHelper.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

#import <Foundation/Foundation.h>
#import "JVMHelper.h"

NSString* javaStringToNSString(JNIEnv *env, jstring javaString) {
	const char* cString = (*env)->GetStringUTFChars(env, javaString, NULL);
	NSString *nsString = [NSString stringWithUTF8String:cString];
	(*env)->ReleaseStringUTFChars(env, javaString, cString);
	
	return nsString;
}

NSArray<NSString *>* javaStringArrayToNSArray(JNIEnv *env, jobjectArray javaStringArray) {
	jsize arrayLength = (*env)->GetArrayLength(env, javaStringArray);
	NSMutableArray<NSString *>* nsArray = [NSMutableArray arrayWithCapacity:arrayLength];
	for(int i = 0; i < arrayLength; i++) {
		NSString *string = javaStringToNSString(env, (jstring) (*env)->GetObjectArrayElement(env, javaStringArray, i));
		[nsArray addObject:string];
	}
	
	return nsArray;
}

jint throwNSError(JNIEnv *env, NSError *error) {
	jclass exception = (*env)->FindClass(env, "java/lang/RuntimeException");
	return (*env)->ThrowNew(env, exception, error.description.UTF8String);
}

jobject boxJavaInteger(JNIEnv* env, int value) {
	jclass intClass = (*env)->FindClass(env, "java/lang/Integer");
	jmethodID intConstructor = (*env)->GetMethodID(env, intClass, "<init>", "(I)V");
	return (*env)->NewObject(intClass, intConstructor, value);
}
