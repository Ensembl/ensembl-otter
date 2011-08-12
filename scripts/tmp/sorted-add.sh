#! /bin/bash

set -e
#set -x

input=~/dist/READMEs

laststamp() {
    perl -e 'my @t = sort map { isomod($_) } @ARGV; print "$t[-1]\n"; sub isomod { my $m = (stat(shift()))[9]; my @t=localtime($m);
 return sprintf("%d-%02d-%02d %02d:%02d:%02d", 1900+$t[5], $t[4]+1, @t[3,2,1,0]) }' "$@"
}

dirs=$( ls -d $input/otterlace* | \
    perl -e '@l=split /[ \n]+/, join " ", <>; print map {"$_\n"} sort { nummy($a) cmp nummy($b) } @l; sub nummy { (shift) =~ m{(\d.*)} ? $1 : "-" }'
    )

echo sorted=$dirs

for readme in $dirs; do
    authdate=$( laststamp $readme/ReadMe.rtfd/* )
    info=$( ls -lT $readme/ReadMe.rtfd/* | perl -pe 'BEGIN{ $dir=shift } s/^.*? 1 .*?\d+//; s{$dir/*}{}' $input )

    rm -rf docs/ReadMe.rtfd
    cp -Rp $readme/ReadMe.rtfd docs/
    git add -A docs
    git commit --author "James Gilbert <jgrg@sanger.ac.uk>" --date "$authdate" -m "$( printf "ReadMe.rtfd contents from %s.\n\n%s" "$(basename $readme)" "$info") " \
        || echo "Commit: returncode $?"

    # sleep 2

done
