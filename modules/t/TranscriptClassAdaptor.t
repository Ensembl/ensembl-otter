
use lib 't';

BEGIN { $| = 1; print "1..8\n"; }
my $loaded = 0;
END {print "not ok 1\n" unless $loaded;}

use OtterTestDB;

use Bio::Otter::DBSQL::TranscriptClassAdaptor;
use Bio::Otter::TranscriptClass;

$loaded = 1;
print "ok 1\n";

# Database will be dropped when this
# object goes out of scope
my $otter_test = OtterTestDB->new;
print ($otter_test ? "ok 2\n" : "not ok 2\n");

my $db = $otter_test->get_DBSQL_Obj;

print ($db ? "ok 3\n" : "not ok 3\n");

my $adaptor = $db->get_TranscriptClassAdaptor();

print ($adaptor ? "ok 4\n" : "not ok 4\n");


my $obj1 =  new Bio::Otter::TranscriptClass(-name => 'CDS',
                                            -description => 'protein coding gene');

my $obj2 =  new Bio::Otter::TranscriptClass(-name        => 'transcript',
					    -description => 'predicted transcript - no CDS');

my $obj3 =  new Bio::Otter::TranscriptClass(-name        => 'transcript',
					    -description => 'different description');


print ("ok 5\n");


$adaptor->store($obj1);
$adaptor->store($obj2);

print "ok 6\n";

my $newobj1 = $adaptor->fetch_by_dbID(1);


print "DBID   " . $newobj1->dbID . "\n";
print "NAME   " . $newobj1->name . "\n";
print "DESC   " . $newobj1->description . "\n";

print "ok 7\n";
my $newobj2 = $adaptor->fetch_by_name('transcript');

print "DBID   " . $newobj2->dbID . "\n";
print "NAME   " . $newobj2->name . "\n";
print "DESC   " . $newobj2->description . "\n";

print "ok 8\n";

#eval {
#  $adaptor->store($obj3);
#}; 
#if ($@ =~ /uplicate/) {
#   print "ok 9\n";
#}
