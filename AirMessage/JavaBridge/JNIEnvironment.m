//
// Created by Cole Feuer on 2021-10-11.
//

#import <Foundation/Foundation.h>
#import "JNIEnvironment.h"

jstring getAppVersion(JNIEnv *env, jclass thisClass) {
    return (*env)->NewStringUTF(env, [NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] UTF8String]);
}

jint getAppVersionCode(JNIEnv *env, jclass thisClass) {
    return [NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] integerValue];
}

void registerJNIEnvironment(JNIEnv *env) {
    JNINativeMethod methods[] = {
            {"getAppVersion", "()Ljava/lang/String;", getAppVersion},
            {"getAppVersionCode", "()I", getAppVersionCode},
    };
    (*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIEnvironment"), methods, sizeof(methods) / sizeof(methods[0]));
}