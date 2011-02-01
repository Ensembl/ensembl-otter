use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 17;}

use OtterTestDB;

use Bio::Otter::DBSQL::AuthorAdaptor;
use Bio::Otter::Author;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $author_adaptor = $db->get_AuthorAdaptor();

ok($author_adaptor);

my $author1 = new Bio::Otter::Author(-name => 'michele',
				     -email => 'michele@sanger.ac.uk');

my $author2 = new Bio::Otter::Author(-name => 'Ewan',
				     -email => 'birney@ebi.ac.uk');

my $author3 = new Bio::Otter::Author(-name => 'searle',
				     -email => 'searle@sanger.ac.uk');

ok(1);


$author_adaptor->store($author1);
$author_adaptor->store($author2);
$author_adaptor->store($author3);

ok($author1->dbID == 1);
ok($author2->dbID == 2);
ok($author3->dbID == 3);

my $newauthor1 = $author_adaptor->fetch_by_name("michele");

ok($newauthor1->dbID == 1);
ok($newauthor1->name eq 'michele');
ok($newauthor1->email eq 'michele@sanger.ac.uk');


my $newauthor2 = $author_adaptor->fetch_by_email("searle\@sanger.ac.uk");

ok($newauthor2->dbID == 3);
ok($newauthor2->name eq 'searle');
ok($newauthor2->email eq 'searle@sanger.ac.uk');


my $newauthor3 = $author_adaptor->fetch_by_dbID(2);

ok($newauthor3->dbID == 2);
ok($newauthor3->name eq 'Ewan');
ok($newauthor3->email eq 'birney@ebi.ac.uk');


# Should test deleting as well
