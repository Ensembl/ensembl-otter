use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 50;}

use OtterTestDB;

use Bio::Otter::DBSQL::StableIdAdaptor;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_StableIdAdaptor();

ok($adaptor);

ok(my $gene_id = $adaptor->fetch_new_gene_stable_id);

print "Gene $gene_id\n";

ok(my $tran_id = $adaptor->fetch_new_transcript_stable_id);

print "Tran $tran_id\n";

ok(my $pep_id  = $adaptor->fetch_new_translation_stable_id);

print "Pep id $pep_id\n";

ok(my $exon_id = $adaptor->fetch_new_exon_stable_id);

print "Exon id $exon_id\n";

my $i = 0;

while ( $i < 20) {

    if ($i % 4 == 0) {
	ok(my $gene_id = $adaptor->fetch_new_gene_stable_id);
	print "Gene $gene_id\n";
    }elsif ($i % 4 == 1) {
	ok(my $tran_id = $adaptor->fetch_new_transcript_stable_id);
	print "Tran $tran_id\n";
    }elsif ($i % 4 == 2) {
	ok(my $pep_id = $adaptor->fetch_new_translation_stable_id);
	print "Ppe $pep_id\n";
    }elsif ($i % 4 == 3) {
	ok(my $exon_id = $adaptor->fetch_new_exon_stable_id);
	print "Exon $exon_id\n";
    }
    $i++;
}

ok(29);

my $sth;
$sth = $adaptor->db->prepare('insert into meta values(\N,"prefix.primary","TEST")');
$sth->execute;

$sth = $adaptor->db->prepare('insert into meta values(\N,"prefix.species","SPECIES")');
$sth->execute;

$sth = $adaptor->db->prepare('insert into meta values(\N,"stable_id.min","14000000")');
$sth->execute;

ok(30);

my $i=0;
while ( $i < 20) {

    if ($i % 4 == 0) {
	ok(my $gene_id = $adaptor->fetch_new_gene_stable_id);
	print "Gene $gene_id\n";
    }elsif ($i % 4 == 1) {
	ok(my $tran_id = $adaptor->fetch_new_transcript_stable_id);
	print "Tran $tran_id\n";
    }elsif ($i % 4 == 2) {
	ok(my $pep_id = $adaptor->fetch_new_translation_stable_id);
	print "Ppe $pep_id\n";
    }elsif ($i % 4 == 3) {
	ok(my $exon_id = $adaptor->fetch_new_exon_stable_id);
	print "Exon $exon_id\n";
    }
    $i++;
}

