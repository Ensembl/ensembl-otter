use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 30;}

use OtterTestDB;

use Bio::Otter::DBSQL::KeywordAdaptor;
use Bio::Otter::Keyword;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_KeywordAdaptor();

ok($adaptor);


my $keyword1 = new Bio::Otter::Keyword(-name               => 'CpG island',
				       -clone_info_id      => 1,
				       );

my $keyword2 = new Bio::Otter::Keyword(-name               => 'XML',
				       -clone_info_id      => 1,
				       );

my $keyword3 = new Bio::Otter::Keyword(-name               => 'XAP-5-like',
				       -clone_info_id      => 2,
				       );

my $keyword4 = new Bio::Otter::Keyword(-name               => 'XAP-5-like',
				       -clone_info_id      => 3
				       );


my @keywords = ($keyword1,$keyword2);


$adaptor->store(@keywords);
$adaptor->store($keyword3);
$adaptor->store($keyword4);

ok($keyword1->dbID == 1);
ok($keyword2->dbID == 2);
ok($keyword3->dbID == 3);
ok($keyword4->dbID == 3);

my @keywords1 = $adaptor->list_by_clone_info_id(1);

foreach my $kk (@keywords1) {
    ok($kk->name ne "");
    ok($kk->clone_info_id == 1);
    ok($kk->dbID == 1 || $kk->dbID ==2);
}

ok(scalar(@keywords1) == 2);

my @keywords2 = $adaptor->list_by_name('XAP-5-like');

ok(scalar(@keywords2) == 2);

foreach my $k (@keywords2) {
    ok ($k->name eq 'XAP-5-like');
    ok ($k->clone_info_id == 2 || $k->clone_info_id == 3);
    ok ($k->dbID == 3);
}

my (@newkey3) = $adaptor->fetch_by_dbID(3);

ok(scalar(@newkey3) == 2);

foreach my $newkey (@newkey3) {

ok($newkey->dbID == 3);
ok($newkey->name eq 'XAP-5-like');
ok($newkey->clone_info_id == 2 || $newkey->clone_info_id == 3);
}
my @keywords3 = $adaptor->get_all_Keyword_names;

ok(scalar(@keywords3) == 3);

print "Keywords @keywords3\n";

# Should test deleting as well
