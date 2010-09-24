#!/bin/sh

touch otterlace.app

release="otterlace_mac_intel_52-16"
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
  open "$sparse"
fi
