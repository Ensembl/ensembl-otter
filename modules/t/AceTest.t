use lib 't';
use Test;
use strict;
use DBI;

BEGIN { $| = 1; plan tests => 7;}

use OtterTestDB;

use Bio::Otter::Converter;

my $otter_test = OtterTestDB->new;

ok($otter_test);


my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $file = "../data/test_db.xml";

ok(open(IN,"<$file"));

ok(my ($genes2,$chr,$chrstart,$chrend,$type,$dna) = Bio::Otter::Converter::XML_to_otter(\*IN,$db));
close(IN);

ok(open(IN,"<$file"));
my $oldxml = "";
while (<IN>) {
  $oldxml .= $_;
}
close(IN);

print "Chr $chr $chrstart $chrend $type " . length($dna) . "\n";

ok($db->assembly_type($type));

#DBI->trace(2);
my $db2 = new Bio::Otter::DBSQL::DBAdaptor(-host => $otter_test->host,
                                           -user => $otter_test->user,
                                           -port => $otter_test->port,
                                           -dbname => $otter_test->dbname);

$db2->assembly_type($type);

my $slice = $db2->get_SliceAdaptor->fetch_by_chr_start_end($chr,$chrstart,$chrend);

ok($dna eq $slice->seq);

ok(my $str = Bio::Otter::Converter::otter_to_ace($slice,$genes2));

open(OUT,">test.ace");
print OUT $str;
close(OUT);




