
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 11 }

use OtterTestDB;

use Bio::Otter::DBSQL::GeneNameAdaptor;
use Bio::Otter::GeneName;

ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_GeneNameAdaptor();

ok($adaptor);

my $obj = new Bio::Otter::GeneName(-name         => 'poggy',
				   -gene_info_id => 1);

ok($obj);

$adaptor->store($obj);

ok(1);

my $newobj = $adaptor->fetch_by_name('poggy');

ok(print $newobj->toString . "\n");

my $newobj2 = $adaptor->fetch_by_gene_info_id(1);

ok(print $newobj2->toString . "\n");

ok($obj->equals($newobj));
ok($obj->equals($newobj2));

ok(print $newobj2->toString . "\n");
