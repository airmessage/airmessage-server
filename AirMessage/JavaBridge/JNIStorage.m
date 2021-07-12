//
//  JNIStorage.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-04.
//

#import <Foundation/Foundation.h>
#import "JNIStorage.h"

jobject getDocumentsDirectory(JNIEnv *env, jclass thisClass) {
    NSString *documentsPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject.path;

    jclass fileClass = (*env)->FindClass(env, "java/io/File");
    jmethodID fileInit = (*env)->GetMethodID(env, fileClass, "<init>", "(Ljava/lang/String;)V");
    jobject newFile = (*env)->NewObject(env, fileClass, fileInit, (*env)->NewStringUTF(env, [documentsPath UTF8String]));

    return newFile;
}

jobject getCacheDirectory(JNIEnv *env, jclass thisClass) {
    NSString *documentsPath = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject.path;

    jclass fileClass = (*env)->FindClass(env, "java/io/File");
    jmethodID fileInit = (*env)->GetMethodID(env, fileClass, "<init>", "(Ljava/lang/String;)V");
    jobject newFile = (*env)->NewObject(env, fileClass, fileInit, (*env)->NewStringUTF(env, [documentsPath UTF8String]));

    return newFile;
}

void registerJNIStorage(JNIEnv *env) {
    JNINativeMethod methods[] = {
            {"getDocumentsDirectory", "()Ljava/io/File;", getDocumentsDirectory},
            {"getCacheDirectory", "()Ljava/io/File;", getCacheDirectory},
    };
    (*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIStorage"), methods, sizeof(methods) / sizeof(methods[0]));
}
