
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 13;}

use OtterTestDB;

use Bio::Otter::DBSQL::CloneLockAdaptor;
use Bio::Otter::CloneLock;
use Bio::Otter::Author;

ok(1);

my $otter_test = OtterTestDB->new;

ok(2);

my $db = $otter_test->get_DBSQL_Obj;

ok(3);

my $adaptor = $db->get_CloneLockAdaptor();

ok(4);

my $name = "michele";
my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-name => $name,
                                    -email => $mail);

ok(5);

my $clone_lock = new Bio::Otter::CloneLock(-id       => 'AC003663',
                                           -version  => 1,
					   -author   => $author
					  );

ok(6);

$adaptor->store($clone_lock);

print "DBID " .$clone_lock->dbID . "\n";

ok(7);

my ($newobj) = $adaptor->list_by_author($author);

print "Retrieved lock " . $newobj->id . " " . $newobj->timestamp . " " . $newobj->author->name . "\n";

ok(8);


my ($newobj2) = $adaptor->fetch_by_clone_id('AC003663');

print "Retrieved lock " . $newobj2->id . " " . $newobj2->timestamp . " " . $newobj2->author->name . "\n";

ok(9);

my $newobj3 = $adaptor->fetch_by_dbID($newobj->dbID);


print "Retrieved lock " . $newobj3->id . " " . $newobj3->timestamp . " " . $newobj3->author->name . "\n";

ok(10);

my $newobj4 = $adaptor->fetch_by_clone_id_version('AC003663',1);

print "Retrieved lock " . $newobj2->id . " " . $newobj2->timestamp . " " . $newobj2->author->name . "\n";

ok(11);

$adaptor->remove_by_clone_id_version($newobj3->id,$newobj3->version);

ok(12);

my @newlock = $adaptor->list_by_author($author);

print "Locks " . scalar(@newlock) . "\n";

foreach my $lock (@newlock) {
    print "Retrieved lock " . $lock->id . " " . $lock->timestamp . " " . $lock->author->name . "\n";
}
ok(13);
