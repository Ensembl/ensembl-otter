use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 13;}

use OtterTestDB;

use Bio::Otter::CloneLockBroker;
use Bio::Otter::CloneLock;
use Bio::Otter::Author;

ok(1);

my $testdb = OtterTestDB->new;

ok(2);

my $db = $testdb->get_DBSQL_Obj;

ok(3);

my $broker = new Bio::Otter::CloneLockBroker($db);

ok(4);

my $author1 = new Bio::Otter::Author(-name => "searle",
                                     -email => "searle\@sanger.ac.uk");

my $author2 = new Bio::Otter::Author(-name => "michele",
                                     -email => "michele\@sanger.ac.uk");

ok(5);

$testdb->do_sql_file("../data/tinyassembly.sql");

ok(6);

$db->assembly_type('test_assem');
my $slice1 = $db->get_SliceAdaptor->fetch_by_chr_start_end("CHR",5,95);
my $slice2 = $db->get_SliceAdaptor->fetch_by_chr_start_end("CHR",60,115);

ok(7);

$broker->lock_clones_by_slice($slice1,$author1);

ok(8);

my @locks = $broker->get_CloneLockAdaptor->list_by_author($author1);

ok(scalar(@locks) == 1);

$broker->remove_by_slice($slice1,$author1);

@locks = $broker->get_CloneLockAdaptor->list_by_author($author1);

ok(scalar(@locks) == 0);

ok(scalar($broker->check_no_locks_exist_by_slice($slice1,$author1)) == 0);

$broker->lock_clones_by_slice($slice1,$author1);

# Test for lock contension
eval {
  $broker->lock_clones_by_slice($slice2,$author2);
};
if ($@) {
  print STDERR "Above throw means lock contension check PASSED\n";
}

ok($@);

ok($broker->check_locks_exist_by_slice($slice1,$author1));

