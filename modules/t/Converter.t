
use lib 't';
use Test;
use strict;

use Bio::Otter::Converter;

BEGIN { $| = 1; plan tests => 9;}

ok(1);

my $name = "michele";
my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-dbID  => 1,
				    -name => $name,
                                    -email => $mail);


ok(2);

my $acefile = '../data/annotation.ace';

open(ACE,"<$acefile");
my $fh = \*ACE;

ok(3);

my $genes1 = Bio::Otter::Converter::ace_to_otter($fh);

foreach my $gene (@$genes1) {
  $gene->gene_info->author($author);
}

ok(4);

my $str1;

foreach my $gene (@$genes1) {
  $str1 .=  $gene->toXMLString . "\n";
}
if (-e "../data/annotation.xml") {
  unlink "../data/annotation.xml";
}
open XML,">../data/annotation.xml";

print XML $str1;

close(XML);

ok(5);

open(IN,"<../data/annotation.xml");

my ($genes2,$chr,$chrstart,$chrend) = Bio::Otter::Converter::XML_to_otter(\*IN);

my $str2;

ok(6);

foreach my $gene (@$genes2) {
  $str2 .=  $gene->toXMLString . "\n";
}

ok(7);

ok($str1 eq $str2);
print $str2 . "\n";
open(IN,"../data/annotation.xml.real");

my $str3;

while (<IN>) {
  $str3 .= $_;
}

ok($str1 eq $str3);


