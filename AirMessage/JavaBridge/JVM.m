//
//  JVMTest.mm
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-03.
//

#import "JVM.h"

JavaVM *jvm;

/**
 * Launches the JVM
 * @param jvm A pointer to the JVM to store
 * @return The default JNIEnv
 */
JNIEnv* createJVM(JavaVM **jvm) {
    JNIEnv* env;
    JavaVMInitArgs args;
    JavaVMOption options;
    args.version = JNI_VERSION_10;
    args.nOptions = 1;
	options.optionString = [NSString stringWithFormat:@"%@/%@/%@", @"-Djava.class.path=", NSBundle.mainBundle.resourcePath, @"/Java/airmessage-libs/airmessage-server.jar"].UTF8String;
    args.options = &options;
    args.ignoreUnrecognized = 0;
    int rv = JNI_CreateJavaVM(jvm, (void**)&env, &args);
    if(rv < 0 || !env) {
        printf("Unable to Launch JVM %d\n", rv);
    } else {
        printf("Launched JVM! :)\n");
    }

    return env;
}

/**
 * Gets the JNIEnv for the current thread
 */
JNIEnv* getJNIEnv() {
    JNIEnv *env = nil;
    // Check if the current thread is attached to the VM
    jint get_env_result = (*jvm)->GetEnv(jvm, (void**)env, JNI_VERSION_10);
    if(get_env_result == JNI_EDETACHED) {
        if((*jvm)->AttachCurrentThread(jvm, (void**)env, NULL) == JNI_OK) {
            return env;
        } else {
            // Failed to attach thread. Throw an exception if you want to.
        }
    } else if(get_env_result == JNI_EVERSION) {
        // Unsupported JNI version. Throw an exception if you want to.
    }

    return nil;
}

/**
 * Starts the JVM and registers native methods
 */
bool startJVM() {
    //Create JVM
    JNIEnv *env;
    env = createJVM(&jvm);
    if(env == NULL) return false;

    //Register native methods
    registerJNIPreferences(env);
    registerJNIStorage(env);
    registerJNIUserInterface(env);
	
	//Call main method
	jclass mainClass = (*env)->FindClass(env, "me/tagavari/airmessageserver/server/Main");
	jmethodID mainMethodID = (*env)->GetStaticMethodID(env, mainClass, "main", "([Ljava/lang/String;)V");
	(*env)->CallStaticVoidMethod(env, mainClass, mainMethodID, NULL);
	
    return true;
}
