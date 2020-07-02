#!/bin/sh
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


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
