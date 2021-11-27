#!/bin/sh

#  CopyHeaders.sh
#  AirMessage
#
#  Created by Cole Feuer on 2021-11-27.
#  

HEADERS_INSTALL_DIR="$BUILT_PRODUCTS_DIR"/"$PUBLIC_HEADERS_FOLDER_PATH"
#Copy header files to output
cp -r OpenSSL/Headers/*.h "$HEADERS_INSTALL_DIR"
#List headers in umbrella header
ls OpenSSL/Headers/*.h | xargs basename | sed -Ee "s|(.+\.h)$|#include <OpenSSL\/\1>|" >> "$HEADERS_INSTALL_DIR/OpenSSL.h"
