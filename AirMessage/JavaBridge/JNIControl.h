#include <jni.h>
#import <Foundation/Foundation.h>

@class ClientRegistration;

void jniStartServer(void);
void jniStopServer(void);
NSMutableArray<ClientRegistration *>* jniGetClients(void);
