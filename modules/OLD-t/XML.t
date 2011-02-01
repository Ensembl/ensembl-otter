
use lib 't';
use Test;
use strict;

use Bio::Otter::Converter;

BEGIN { $| = 1; plan tests => 10;}

ok(1);

my $xmlfile = '../data/9p12.xml';
#my $xmlfile = $ARGV[0];

open(XML,"<$xmlfile");
my $fh = \*XML;

ok(2);

my ($genes,$slice,$seq,$tile) = Bio::Otter::Converter::XML_to_otter($fh);

close(XML);
my $str1;
open(XML,"<$xmlfile");
while (<XML>) {
 $str1 .= $_;
}


ok(3);

if (-e "../data/9p12.xml.new") {
  unlink "../data/9p12.xml.new";
}
open XML,">../data/9p12.xml.new";

ok(4);

my $str2 = Bio::Otter::Converter::genes_to_XML_with_Slice($slice,$genes,1,$tile,$seq);

ok(5);

$str2 .= "\n";
print XML $str2;

close(XML);

ok($str1 eq $str2);


my $str3 = Bio::Otter::Converter::otter_to_ace($slice,$genes,$tile,$seq);
open (ACE,">../data/9p12.ace");
print ACE $str3  . "\n";
close(ACE);

open (ACE2,"<../data/9p12.ace");


my ($genes,$frags,$type,$dna,$chr,$chrstart,$chrend) = Bio::Otter::Converter::ace_to_otter(\*ACE2);

