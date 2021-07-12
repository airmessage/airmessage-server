#import <Foundation/Foundation.h>
#import "JNIPreferences.h"
#import "JNIStorage.h"
#import "JNIUserInterface.h"

#include <jni.h>

bool startJVM();
JNIEnv* getJNIEnv();