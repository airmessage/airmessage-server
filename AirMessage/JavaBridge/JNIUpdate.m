//
// Created by Cole Feuer on 2021-10-23.
//

#import "JNIUpdate.h"
#import "AirMessage-Swift.h"
#import "JVMHelper.h"

#define CLASSNAME "me/tagavari/airmessageserver/jni/JNIUpdate"

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
        jmethodID updateDataInit = (*env)->GetMethodID(env, updateDataClass, "<init>", "(I[ILjava/lang/String;Ljava/lang/String;Z)V");

        jintArray protocolRequirement = nsArrayToJavaIntArray(env, updateStruct.protocolRequirement);
        jstring versionName = (*env)->NewStringUTF(env, updateStruct.versionName.UTF8String);
        jstring notes = (*env)->NewStringUTF(env, updateStruct.notes.UTF8String);
        jobject newUpdateData = (*env)->NewObject(env, updateDataClass, updateDataInit,
                updateStruct.id, protocolRequirement, versionName, notes, updateStruct.downloadExternal);
        return newUpdateData;
    }
}

jboolean installUpdate(JNIEnv *env, jclass thisClass, jint updateID) {
    __block BOOL result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        //Checking if the current update matches the update ID
        UpdateStruct *pendingUpdate = UpdateHelper.pendingUpdate;
        if(pendingUpdate == nil || pendingUpdate.id != updateID) {
            result = NO;
            return;
        }

        //Installing the update
        result = [UpdateHelper
                installWithUpdate:pendingUpdate
                       onProgress: nil
                        onSuccess: nil
                          onError: ^(UpdateErrorCode code, NSString *message) {
                              //Create the error object
                              jclass updateErrorClass = (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/record/JNIUpdateError");
                              jmethodID updateErrorInit = (*env)->GetMethodID(env, updateErrorClass, "<init>", "(ILjava/lang/String;)V");
                              jobject updateErrorObject = (*env)->NewObject(env, updateErrorClass, updateErrorInit,
                                      code, (*env)->NewStringUTF(env, message.UTF8String));

                              //Notify the Java side
                              jclass class = (*env)->FindClass(env, CLASSNAME);
                              jmethodID methodID = (*env)->GetStaticMethodID(env, class, "notifyUpdateError", "(Lme/tagavari/airmessageserver/jni/record/JNIUpdateError;)V");
                              (*env)->CallStaticVoidMethod(env, class, methodID, updateErrorObject);
                          }];
    });

    return (jboolean) result;
}

void registerJNIUpdate(JNIEnv *env) {
    JNINativeMethod methods[] = {
            {"getUpdate", "()Lme/tagavari/airmessageserver/jni/record/JNIUpdateData;", getUpdate},
            {"installUpdate", "(I)Z", installUpdate},
    };
    (*env)->RegisterNatives(env, (*env)->FindClass(env, CLASSNAME), methods, sizeof(methods) / sizeof(methods[0]));
}
