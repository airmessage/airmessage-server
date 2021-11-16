//
//  ObjC.h
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

#ifndef ObjCException_h
#define ObjCException_h

#import <Foundation/Foundation.h>

@interface ObjC : NSObject

+ (BOOL)catchException:(void(NS_NOESCAPE ^)(void))tryBlock error:(__autoreleasing NSError **)error;

@end

#endif /* ObjCException_h */
