
use lib 't';

BEGIN { $| = 1; print "1..3\n"; }
my $loaded = 0;
END {print "not ok 1\n" unless $loaded;}

use OtterTestDB;
use Bio::EnsEMBL::DBLoader;

$loaded = 1;
print "ok 1\n";

# Database will be dropped when this
# object goes out of scope
my $otter_test = OtterTestDB->new;
print ($otter_test ? "ok 2\n" : "not ok 2\n");

my $db = $otter_test->get_DBSQL_Obj;

print ($db ? "ok 3\n" : "not ok 3\n");
