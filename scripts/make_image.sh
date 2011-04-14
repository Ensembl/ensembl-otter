#!/bin/sh

touch otterlace.app

# we bump the release number and commit this file, just BEFORE making the dist image
release="otterlace_mac_intel-54.02"

sparse="$release.sparseimage"
dmg="$release.dmg"

if [ -e "$sparse" ]
then
  echo "Converting sparseimage to $dmg"
  if [ -e "/Volumes/$release" ]
  then
    echo "Error: Disk $release is mounted"
    exit 1
  fi
  rm "$release.dmg"
  hdiutil convert "$sparse" -format UDBZ -o "$dmg"
else
  echo "Creating sparseimage $sparse"
  hdiutil create -fs HFS+ -volname "$release" "$sparse"
  hdiutil mount "$sparse"
fi
