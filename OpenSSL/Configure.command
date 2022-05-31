#!/bin/sh -e

#  Configure.sh
#  AirMessage
#
#  Created by Cole Feuer on 2021-11-27.
#  

cd "$(dirname "$0")"

OPENSSL_VERSION=3.0.3

#Download OpenSSL
echo "Downloading OpenSSL version $OPENSSL_VERSION..."
curl https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz --output openssl-$OPENSSL_VERSION.tar.gz --silent
tar -xf openssl-$OPENSSL_VERSION.tar.gz
pushd openssl-$OPENSSL_VERSION

#Build for Intel
echo "Building OpenSSL $OPENSSL_VERSION for Intel..."
export MACOSX_DEPLOYMENT_TARGET=10.10
./Configure darwin64-x86_64 no-deprecated no-shared
make
mv libcrypto.a ../libcrypto-x86_64.a
make clean

#Build for Apple Silicon
echo "Building OpenSSL $OPENSSL_VERSION for Apple Silicon..."
export MACOSX_DEPLOYMENT_TARGET=11.0
./Configure darwin64-arm64 no-deprecated no-shared
make
mv libcrypto.a ../libcrypto-arm64.a

popd

echo "Finalizing OpenSSL $OPENSSL_VERSION..."

#Combine libraries
lipo -create -output libcrypto.a libcrypto-x86_64.a libcrypto-arm64.a

#Copy headers
mkdir -p Headers
cp -r openssl-$OPENSSL_VERSION/include/openssl/. Headers/

#Fix inttypes.h
find Headers -type f -name "*.h" -exec sed -i "" -e "s/include <inttypes\.h>/include <sys\/types\.h>/g" {} \;

#Clean up
rm libcrypto-x86_64.a libcrypto-arm64.a openssl-$OPENSSL_VERSION.tar.gz
rm -r openssl-$OPENSSL_VERSION

echo "Successfully built OpenSSL $OPENSSL_VERSION"
