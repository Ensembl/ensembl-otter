
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 11;}

use Bio::Otter::Converter;
use Bio::Otter::AnnotationBroker;

use OtterTestDB;

ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

$testdb->do_sql_file("../data/assembly.sql");

ok(3);

open(XML1,"<../data/annotation1.xml");

ok(4);

my ($genes1,$slice,$seqstr,$tiles) = Bio::Otter::Converter::XML_to_otter(\*XML1);

print "Done converstion\n";
my $xmlstr = Bio::Otter::Converter::genes_to_XML_with_Slice($slice, $genes1, 1,$tiles);

print $xmlstr . "\n";
$db->assembly_type('test_otter');

my $sa = $db->get_SliceAdaptor;

my $slice1 = $sa->fetch_by_chr_start_end($slice->chr_name,$slice->chr_start,$slice->chr_end);

close(XML1);

open(XML2,"<../data/annotation2.xml");

ok(5);

my ($genes2,$slice2) = Bio::Otter::Converter::XML_to_otter(\*XML2);


ok($slice->chr_name eq $slice2->chr_name && $slice->chr_start == $slice2->chr_start && $slice->chr_end == $slice2->chr_end);

close(XML2);

ok(7);

my $ab = new Bio::Otter::AnnotationBroker($db);
my $aga = $db->get_AnnotatedGeneAdaptor;

ok(8);

my $an = new Bio::EnsEMBL::Analysis(-logic_name => 'otter',
				    -gff_source => 'otter',
				    -gff_feature=> 'otter');


ok($db->get_AnalysisAdaptor->store($an));

ok(10);

foreach my $g (@$genes1) {
    $g->analysis($an);
    $aga->attach_to_Slice($g,$slice1);
    $aga->store($g);
}


foreach my $g (@$genes2) {
    $g->analysis($an);
}

# Genes1 - dbID 1
# Genes2 - dbID 2
print "Comparing *******\n";
$ab->compare_annotations($genes1,$genes2,$slice1);

#$testdb->pause;
ok(11);
print "Fetching **********\n";

my @genes3 = @{$aga->fetch_by_Slice($slice1)};

foreach my $g (@$genes2) {
    #print "Gene 2 dbID " . $g->dbID . "\n";
    print $g->gene_info->toString . "\n";

    foreach my $tran (@{$g->get_all_Transcripts}) {
	#print "Tran dbID " . $tran->dbID . "\n";
	print $tran->transcript_info->toString . "\n";
    }
}

foreach my $g (@genes3) {
    print "Gene 3 dbID " . $g->dbID . "\n";
    print $g->gene_info->toString . "\n";

    foreach my $tran (@{$g->get_all_Transcripts}) {
	print "Tran dbID " . $tran->dbID . "\n";
	print $tran->transcript_info->toString . "\n";
    }
}
print "Comparing fetch ***********\n";

$ab->compare_annotations($genes2,\@genes3,$slice1);

#$testdb->pause;
