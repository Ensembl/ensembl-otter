use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 64;}

use Bio::Otter::GeneInfo;
use Bio::Otter::GeneRemark;
use Bio::Otter::GeneName;
use Bio::Otter::GeneSynonym;
use Bio::Otter::Author;
use Bio::Otter::DBSQL::GeneInfoAdaptor;

use OtterTestDB;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_GeneInfoAdaptor();

ok($adaptor);

my $author = new Bio::Otter::Author(-name  => 'michele',
				    -email => 'michele@sanger.ac.uk');

my $name = new Bio::Otter::GeneName(-name => 'poggene');

ok($author);

my $remark1 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the first remark");
my $remark2 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the second remark");
my $remark3 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the third remark");
my $remark4 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the fourth remark");
my $remark5 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the fifth remark");

my $syn1 = new Bio::Otter::GeneSynonym(-name => 'pog1');
my $syn2 = new Bio::Otter::GeneSynonym(-name => 'pog2');
my $syn3 = new Bio::Otter::GeneSynonym(-name => 'pog3');

my $syn = [$syn1,$syn2,$syn3];

my $geneinfo = new Bio::Otter::GeneInfo(-gene_stable_id  => 'ENSG00000023222',
					-author          => $author,
					-synonym         => $syn,
					-name            => $name,
					-remark          => [$remark1,$remark2]);


ok($geneinfo->toString);

my @rem = ($remark3,$remark4,$remark5);

ok($geneinfo->remark(@rem));

print "Name " . $geneinfo->name . "\n";

ok($adaptor->store($geneinfo));

my $newgi = $adaptor->fetch_by_stable_id('ENSG00000023222');

ok($newgi);

ok($newgi->dbID == 1);
ok($newgi->author);
ok($newgi->author->name eq 'michele');
ok($newgi->author->email eq 'michele@sanger.ac.uk');
ok($newgi->gene_stable_id eq 'ENSG00000023222');
ok($newgi->timestamp);

my @remarks = $newgi->remark;

ok(scalar(@remarks) == 5);

foreach my $rem (@remarks) {
    ok($rem->gene_info_id == 1);
    ok($rem->dbID);
    ok($rem->remark);
}

my @syn = $newgi->synonym;

print "Syn @syn\n";

ok(scalar(@syn) == 3);

my $newname = $newgi->name;

ok($newname->name eq 'poggene');
ok($newname->dbID == 1);
ok($newname->gene_info_id == $newgi->dbID);

my $newgi2 = $adaptor->fetch_by_dbID(1);

ok($newgi2);

ok($newgi2->dbID == 1);
ok($newgi2->author);
ok($newgi2->author->name eq 'michele');
ok($newgi2->author->email eq 'michele@sanger.ac.uk');
ok($newgi2->gene_stable_id eq 'ENSG00000023222');
ok($newgi2->timestamp);

my @remarks2 = $newgi2->remark;

ok(scalar(@remarks2) == 5);

foreach my $rem (@remarks2) {
    ok($rem->gene_info_id == 1);
    ok($rem->dbID);
    ok($rem->remark);
}

my @newsyn = $newgi2->synonym;

ok(scalar(@newsyn) == 3);

foreach my $s (@newsyn) {
    ok($s->gene_info_id == 1);
}

my $newname2 = $newgi2->name;

ok($newname2->name eq 'poggene');
ok($newname2->gene_info_id == 1);

    
