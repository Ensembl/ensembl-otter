use lib 't';

use Test;
use strict;

BEGIN { $| = 1; plan tests => 17 }

use OtterTestDB;

use Bio::Otter::DBSQL::GeneSynonymAdaptor;
use Bio::Otter::GeneSynonym;

ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_GeneSynonymAdaptor();

ok($adaptor);

my $obj1 = new Bio::Otter::GeneSynonym(-name         => 'pog1',
				      -gene_info_id => 1);
my $obj2 = new Bio::Otter::GeneSynonym(-name         => 'pog2',
				      -gene_info_id => 2);
my $obj3 = new Bio::Otter::GeneSynonym(-name         => 'pog3',
				       -gene_info_id => 2);


ok($obj1);
ok($obj2);
ok($obj3);

ok($adaptor->store($obj1));
ok($adaptor->store($obj2));
ok($adaptor->store($obj3));

my @newobj = $adaptor->list_by_name('pog1');

ok(print $newobj[0]->toString . "\n");

my @newobj2 = $adaptor->list_by_gene_info_id(2);

ok(scalar(@newobj2) == 2);

foreach my $obj (@newobj2) {
    ok(print $obj->toString . "\n");
    ok($obj->gene_info_id == 2);
}

ok($obj1->equals($newobj[0]));
