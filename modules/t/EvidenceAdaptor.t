
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 9 }

use OtterTestDB;

use Bio::Otter::DBSQL::EvidenceAdaptor;
use Bio::Otter::Evidence;


ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_EvidenceAdaptor();

ok($adaptor);

my $obj2 = new Bio::Otter::Evidence(-name => 'pog',
                                   -transcript_info_id  => 2,
				   -xref_id        => 3,
				   -type           => 'Protein');
my $obj = new Bio::Otter::Evidence(-name => 'AC897312',
                                   -transcript_info_id  => 2,
                                   -db_name        => 'dbEST',
				   -type           => 'EST');

my @ev = ($obj,$obj2);

#print Bio::Otter::Evidence->toString($obj) . "\n";

ok($obj);

$adaptor->store(@ev);

ok(1);

my $newobj = $adaptor->fetch_by_dbID(1);

print Bio::Otter::Evidence->toString($newobj) . "\n";

ok(1);

my @newobj2 = $adaptor->list_by_transcript_info_id(2);

foreach my $obj (@newobj2) {
  print Bio::Otter::Evidence->toString($obj) . "\n";
}
ok(1);

my @obj2 = $adaptor->list_by_type('EST');

print Bio::Otter::Evidence->toString(@obj2) . "\n";

ok(1);




