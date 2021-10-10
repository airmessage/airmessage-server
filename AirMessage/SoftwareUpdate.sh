#!/bin/sh

#  SoftwareUpdate.sh
#  AirMessage
#
#  Created by Cole Feuer on 2021-10-10.
#  

pid="$0"
srcFile="$1"
dstFile="$2"

#Wait for app to exit
while kill -0 "$pid"; do
  sleep 0.5
done

#Delete old AirMessage installation
rm -rf "$dstFile"

#Move the new app to the target directory
mv "$srcFile" "$dstFile"

#Remove the source directory
rm -r "$(dirname "$srcFile")"

#Wait for app to be registered
sleep 1

#Open the new app
for i in 1 2 3 4 5
do
	open /Applications/AirMessage.app && break || sleep 1
done