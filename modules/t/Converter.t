
use lib 't';
use Test;
use strict;

use Bio::Otter::Converter;

BEGIN { $| = 1; plan tests => 10;}

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

my $str1 = "<otter>\n<sequenceset>\n";

foreach my $gene (@$genes1) {
  $str1 .=  $gene->toXMLString . "\n";
}
if (-e "../data/annotation.xml") {
  unlink "../data/annotation.xml";
}
open XML,">../data/annotation.xml";

$str1 .= "</sequenceset>\n</otter>\n";
print XML $str1;

close(XML);

ok(5);

open(IN,"<../data/annotation.xml");

my ($genes2,$chr,$chrstart,$chrend) = Bio::Otter::Converter::XML_to_otter(\*IN);

my $str2 = "<otter>\n<sequenceset>\n";

ok(6);

foreach my $gene (@$genes2) {
  $str2 .=  $gene->toXMLString . "\n";
}
$str2 .= "</sequenceset>\n</otter>\n";
ok(7);
open (XML2,">../data/annotation.new.xml");
print XML2 $str2;
close(XML2);
ok($str1 eq $str2);

print $str1 . "\n";
print $str2 . "\n";

open(IN,"../data/annotation.xml.real");

my $str3;

while (<IN>) {
  $str3 .= $_;
}

ok($str1 eq $str3);
ok($str2 eq $str3);


