$number;
for ($k = 1; $k < 26; $k++) {
    $name = "chr".$k.".agp";
    open(FH,$name);
    while(<FH>) {
        if (/\s+F\s+/) {
            $number++;
        }
    }
    print "$name\t$number\n";
    $number = 0;
    close FH;
}
open(FH,"chrU.agp");
while (<FH>) {
        if (/\s+F\s+/) {
            $number++;
        }
}
print "chrU.agp\t$number\n";
