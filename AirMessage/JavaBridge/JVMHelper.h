//
//  JVMHelper.h
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-24.
//

#include <jni.h>

NSString* javaStringToNSString(JNIEnv *env, jstring javaString);
NSArray<NSString *>* javaStringArrayToNSArray(JNIEnv *env, jobjectArray javaStringArray);
jintArray nsArrayToJavaIntArray(JNIEnv *env, NSArray<NSNumber *> *array);
jint throwNSError(JNIEnv *env, NSError *error);
jobject boxJavaInteger(JNIEnv* env, int value);