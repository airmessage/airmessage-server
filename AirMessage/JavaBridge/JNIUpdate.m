//
// Created by Cole Feuer on 2021-10-23.
//

#import "JNIUpdate.h"
#import "AirMessage-Swift.h"

jobject getUpdate(JNIEnv *env, jclass thisClass) {
    //Get update data from main thread
	__block UpdateStruct *updateStruct = nil;
	dispatch_sync(dispatch_get_main_queue(), ^{
		updateStruct = UpdateHelper.pendingUpdate;
    });

    //Convert to a Java object
    if(updateStruct == nil) {
        return NULL;
    } else {
        jclass updateDataClass = (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/record/JNIUpdateData");
        jmethodID updateDataInit = (*env)->GetMethodID(env, updateDataClass, "<init>", "(ILjava/lang/String;Ljava/lang/String;Z)V");
        jobject newUpdateData = (*env)->NewObject(env, updateDataClass, updateDataInit,
                updateStruct.id, (*env)->NewStringUTF(env, updateStruct.versionName.UTF8String), (*env)->NewStringUTF(env, updateStruct.notes.UTF8String), updateStruct.downloadExternal);
        return newUpdateData;
    }
}

jboolean installUpdate(JNIEnv *env, jclass thisClass, jint updateID) {
    return NO;
}

void registerJNIUpdate(JNIEnv *env) {
    JNINativeMethod methods[] = {
            {"getUpdate", "()Lme/tagavari/airmessageserver/jni/record/JNIUpdateData;", getUpdate},
            {"installUpdate", "(I)Z", installUpdate},
    };
    (*env)->RegisterNatives(env, (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIStorage"), methods, sizeof(methods) / sizeof(methods[0]));
}
