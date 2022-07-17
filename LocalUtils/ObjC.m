//
//  ObjC.m
//  AirMessage
//
//  Created by Cole Feuer on 2021-11-16.
//

#import "ObjC.h"

@implementation ObjC

+ (BOOL)catchException:(void(NS_NOESCAPE ^)(void))tryBlock error:(__autoreleasing NSError **)error {
	@try {
		tryBlock();
		return YES;
	}
	@catch (NSException *exception) {
		*error = [[NSError alloc] initWithDomain:exception.name code:0 userInfo:exception.userInfo];
		return NO;
	}
}

@end
