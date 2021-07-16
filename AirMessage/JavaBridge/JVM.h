#import <Foundation/Foundation.h>

#include <jni.h>

bool startJVM(void);
void stopJVM(void);
JNIEnv* getJNIEnv(void);
void handleException(JNIEnv *env);
