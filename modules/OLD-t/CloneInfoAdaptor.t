
use lib 't';

BEGIN { $| = 1; print "1..7\n"; }
my $loaded = 0;
END {print "not ok 1\n" unless $loaded;}

use OtterTestDB;

use Bio::Otter::DBSQL::CloneInfoAdaptor;
use Bio::Otter::CloneInfo;
use Bio::Otter::Author;

$loaded = 1;
print "ok 1\n";

# Database will be dropped when this
# object goes out of scope
my $otter_test = OtterTestDB->new;
print ($otter_test ? "ok 2\n" : "not ok 2\n");

my $db = $otter_test->get_DBSQL_Obj;

print ($db ? "ok 3\n" : "not ok 3\n");

my $adaptor = $db->get_CloneInfoAdaptor();

print ($adaptor ? "ok 4\n" : "not ok 4\n");

my $name = "michele";
my $mail = "michele\@sanger.ac.uk";

my $author = new Bio::Otter::Author(-dbID  => 1,
                                    -name => $name,
                                    -email => $mail);

print ($author ? "ok 5\n" : "not ok 5\n");

my $remark1 = new Bio::Otter::CloneRemark(-remark => "remark 1");
my $remark2 = new Bio::Otter::CloneRemark(-remark => "remark 2");

my @remarks = ($remark1,$remark2);

my $keyword1 = new Bio::Otter::Keyword(-name => "keyword 1");
my $keyword2 = new Bio::Otter::Keyword(-name => "keyword 2");

my @keywords = ($keyword1,$keyword2);


my $cloneinfo = new Bio::Otter::CloneInfo(
                                          -clone_id  => 1,
                                          -author    => $author,
                                          -is_active => 1,
                                          -remark    => \@remarks,
                                          -keyword   => \@keywords,
                                          -source    => "SANGER");


$adaptor->store($cloneinfo);

print "ok 6\n";

my $newinfo = $adaptor->fetch_by_dbID(1);

print "DBID   " . $newinfo->dbID . "\n";
print "CLONE  " . $newinfo->clone_id . "\n";
print "ACTIVE " . $newinfo->is_active . "\n";
print "SOURCE " . $newinfo->source . "\n";
print "TIME   " . $newinfo->timestamp . "\n";
print "AUTHOR " .$newinfo->author->name . " " . $newinfo->author->email . " " . $newinfo->author->dbID . "\n";
foreach my $keyword ($newinfo->keyword) {
  print "KEYWORD " . $keyword->name . " " . $keyword->dbID . "\n";
}
foreach my $remark ($newinfo->remark) {
  print "REMARK " . $remark->remark . " " . $remark->dbID . "\n";
}

print "ok 7\n";

