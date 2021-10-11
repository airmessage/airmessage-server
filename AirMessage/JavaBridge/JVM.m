//
//  JVMTest.mm
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-03.
//

#import "JVM.h"

#import "JNIPreferences.h"
#import "JNIStorage.h"
#import "JNIUserInterface.h"
#import "JNIMessage.h"
#import "JNILogging.h"
#import "JNIEnvironment.h"

JavaVM *jvm;
JNIEnv *defaultEnv;

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
	options.optionString = (char *) [NSString stringWithFormat:@"%@/%@/%@", @"-Djava.class.path=", NSBundle.mainBundle.resourcePath, @"/Java/airmessage-libs/airmessage-server.jar"].UTF8String;
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
JNIEnv* getJNIEnv(void) {
    /* JNIEnv *env = nil;
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

    return nil; */
	
	return defaultEnv;
}

/**
 * Starts the JVM and registers native methods
 */
bool startJVM(void) {
    //Create JVM
    JNIEnv *env;
    env = createJVM(&jvm);
    if(env == NULL) return false;
	
	defaultEnv = env;

    //Register native methods
    registerJNIPreferences(env);
    registerJNIStorage(env);
    registerJNIUserInterface(env);
    registerJNIMessage(env);
	registerJNILogging(env);
	registerJNIEnvironment(env);

	//Call main method
	jclass mainClass = (*env)->FindClass(env, "me/tagavari/airmessageserver/server/Main");
	jmethodID mainMethodID = (*env)->GetStaticMethodID(env, mainClass, "main", "([Ljava/lang/String;)V");
	(*env)->CallStaticVoidMethod(env, mainClass, mainMethodID, NULL);
	handleException(env);
	
    return true;
}

/**
 * Cleans up the JVM
 */
void stopJVM(void) {
    //Call System.exit
    JNIEnv *env = getJNIEnv();
    jclass systemClass = (*env)->FindClass(env, "java/lang/System");
    jmethodID exitMethod = (*env)->GetStaticMethodID(env, systemClass, "exit", "(I)V");
    (*env)->CallStaticVoidMethod(env, systemClass, exitMethod, 0);

    //Wait for JVM to exit
	(*jvm)->DestroyJavaVM(jvm);
}

void handleException(JNIEnv *env) {
	if(!(*env)->ExceptionCheck(env)) return;
	
	//Log the error to stderr
	//(*env)->ExceptionDescribe(env);
	
	//Get exception information
	jthrowable exceptionObject = (*env)->ExceptionOccurred(env);
	
	jclass utilClass = (*env)->FindClass(env, "me/tagavari/airmessageserver/jni/JNIUtil");
	jmethodID utilDescribeMethodID = (*env)->GetStaticMethodID(env, utilClass, "describeThrowable", "(Ljava/lang/Throwable;)Ljava/lang/String;");
	jstring description = (jstring) (*env)->CallStaticObjectMethod(env, utilClass, utilDescribeMethodID, exceptionObject);
	const char *descriptionString = (*env)->GetStringUTFChars(env, description, NULL);
	
	//Raise an error
	[NSException raise:@"JavaException" format:@"%@", [NSString stringWithUTF8String:descriptionString]];
}
