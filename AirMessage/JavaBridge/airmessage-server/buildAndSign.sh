SIGNATURE=$1 # Apple signing ID: "Developer ID Application: Developer Name (DUCNFCN445)"
NOTARIZATION_USERNAME=$2 # Apple ID username: "developer@example.com"
NOTARIZATION_PASSWORD=$3 # Apple ID password Keychain listing: "AC_PASSWORD"
NOTARIZATION_PROVIDER=$4 # Team provider short name: "4RYZSDG57V"

VERSION=$(./gradlew -q printVersionName)

JDEPS="java.base,java.desktop,java.logging,java.sql,java.xml,java.datatransfer,java.compiler,jdk.unsupported,java.naming,jdk.crypto.ec,jdk.httpserver"
OUTPUT_DIR="build/app"
APP_FILE="$OUTPUT_DIR/AirMessage.app"
PACKAGE_FILE="$OUTPUT_DIR/server-v$VERSION.zip"

echo "Preparing AirMessage Server v$VERSION"

#Build webpack
npm install --prefix connectauth
npm run build --prefix connectauth

if [ -d "src/main/resources/connectsite" ]
then
    rm -rf src/main/resources/connectsite/*
else
    mkdir src/main/resources/connectsite
fi
cp -r connectauth/build/* src/main/resources/connectsite

#Clean up old files
./gradlew clean

#Assemble app files
./gradlew build
./gradlew copyToLib

#Prepare tmp directory
mkdir build/libs/tmp
pushd build/libs/tmp

#Sign native JAR libraries
if [ -z "$SIGNATURE" ]
then
	echo "Skipping re-signing dependencies"
else
	for f in ../*.jar;
	do
		echo "Re-signing $(basename "$f")"

		jar xf "$f" #Unpack
		rm "$f" #Delete original JAR
		find -E . -regex ".*\.(dylib|jnilib)" -print0 | xargs codesign --force --verbose --sign "$SIGNATURE" #Codesign dynamic libraries
		jar cmf META-INF/MANIFEST.MF "$f" ./* #Repack JAR
		rm -r ./* #Empty directory
	done
fi

#Clean up tmp directory
popd
rm -rf build/libs/tmp

#Create app directory
mkdir $OUTPUT_DIR

#Package app
echo "Packaging app"
$JAVA_HOME/bin/jpackage \
	--name "AirMessage" \
	--app-version "$VERSION" \
	--input "build/libs" \
	--main-jar "$(./gradlew -q printJarName)" \
	--main-class "me.tagavari.airmessageserver.server.Main" \
	--type "app-image" \
	--java-options "-XstartOnFirstThread" \
	--add-modules "$JDEPS" \
	--mac-package-identifier "me.tagavari.airmessageserver" \
	--mac-package-name "AirMessage" \
	--mac-package-signing-prefix "airmessage" \
	--icon "AirMessage.icns" \
	--dest $OUTPUT_DIR

#Update app plist
echo "Fixing plist"
plutil -insert LSUIElement -string True "$APP_FILE/Contents/Info.plist" #Hide dock icon
plutil -insert NSAppTransportSecurity -xml "<dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>" "$APP_FILE/Contents/Info.plist" #Enable local networking (for AirMessage Connect sign-in)

#Sign app
if [ -z "$SIGNATURE" ]
then
	echo "Skipping signing app"
else
	echo "Signing app"
	codesign --force --options runtime --entitlements "macos.entitlements" --sign "$SIGNATURE" "$APP_FILE/Contents/runtime/Contents/MacOS/libjli.dylib"
	codesign --force --options runtime --entitlements "macos.entitlements" --sign "$SIGNATURE" "$APP_FILE/Contents/MacOS/AirMessage"
	codesign --force --options runtime --entitlements "macos.entitlements" --sign "$SIGNATURE" "$APP_FILE"
fi

#Package app to ZIP
if [ -z "$NOTARIZATION_PASSWORD" ]
then
	echo "Compressing app for development"
else
	echo "Compressing app for notarization"
fi
ditto -c -k --keepParent "$APP_FILE" "$PACKAGE_FILE"

if [ -z "$NOTARIZATION_PASSWORD" ]
then
	echo "Skipping notarization"
	echo "Successfully built AirMessage Server v$VERSION for development"
else
	#Notarize app
	echo "Uploading app to Apple notarization service"
	REQUEST_UUID=$(xcrun altool --notarize-app \
		--primary-bundle-id "me.tagavari.airmessageserver" \
		--username "$NOTARIZATION_USERNAME" \
		--password "$NOTARIZATION_PASSWORD" \
		--asc-provider "$NOTARIZATION_PROVIDER" \
		--file "$PACKAGE_FILE" \
		| grep RequestUUID | awk '{print $3}')
	rm "$PACKAGE_FILE"

	#Wait for notarization to finish
	echo "Waiting for completion of notarization request $REQUEST_UUID"
	while true; do
		NOTARIZATION_STATUS=$(xcrun altool --notarization-info "$REQUEST_UUID" --username "$NOTARIZATION_USERNAME" --password "$NOTARIZATION_PASSWORD")
		if echo "$NOTARIZATION_STATUS" | grep -q "Status: in progress"; then sleep 20
		elif echo "$NOTARIZATION_STATUS" | grep -q "Status: success"; then break
		else
			>&2 echo "$NOTARIZATION_STATUS"
			exit
		fi
	done

	#Staple ticket
	echo "Stapling ticket"
	xcrun stapler staple "$APP_FILE"

	#Check for signatures
	echo "Verifying files"
	spctl --assess "$APP_FILE"
	codesign --verify "$APP_FILE"

	#Re-compress app
	echo "Compressing final app to $PACKAGE_FILE"
	ditto -c -k --keepParent "$APP_FILE" "$PACKAGE_FILE"

	echo "Successfully built AirMessage Server v$VERSION for distribution"
fi