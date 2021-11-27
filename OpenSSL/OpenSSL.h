//
//  OpenSSL.h
//  OpenSSL
//
//  Created by Cole Feuer on 2021-11-27.
//

#import <Foundation/Foundation.h>

//! Project version number for OpenSSL.
FOUNDATION_EXPORT double OpenSSLVersionNumber;

//! Project version string for OpenSSL.
FOUNDATION_EXPORT const unsigned char OpenSSLVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <OpenSSL/PublicHeader.h>

#include <OpenSSL/conf.h>
#include <OpenSSL/evp.h>
#include <OpenSSL/err.h>
