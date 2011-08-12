#! /bin/bash

set -e
set -x

dest=~/dist/READMEs

for dmg in ~jgrg/dist/*.dmg ~mca/dist/*.dmg; do
    volname=$( basename -s .dmg $dmg )
    printf "\n\n\n\n"
    echo "dmg=$dmg --> volname=$volname"
    hdiutil mount $dmg
    mkdir -p $dest/$volname
    cp -Rpv /Volumes/$volname/ReadMe.rtfd $dest/$volname/

    # avoid "Resource busy" when unmounting...  Finder?
    sleep 5

    umount /Volumes/$volname
done

