use lib 't';
use Test;
use strict;
use DBI;

BEGIN { $| = 1; plan tests => 7;}

use OtterTestDB;

use Bio::Otter::Converter;

my $otter_test = OtterTestDB->new;

ok($otter_test);


my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $file = "../data/test_db.xml";

ok(open(IN,"<$file"));

ok(my ($genes2,$chr,$chrstart,$chrend,$type,$dna) = Bio::Otter::Converter::XML_to_otter(\*IN,$db));
close(IN);

my $db2 = new Bio::Otter::DBSQL::DBAdaptor(-host => $otter_test->host,
                                           -user => $otter_test->user,
                                           -port => $otter_test->port,
                                           -dbname => $otter_test->dbname);

$db2->assembly_type($type);

my $slice = $db2->get_SliceAdaptor->fetch_by_chr_start_end($chr,$chrstart,$chrend);

my $analysis = new Bio::EnsEMBL::Analysis(-logic_name => 'otter');
$db->get_AnalysisAdaptor->store($analysis);

my %transeq;

foreach my $gene (@$genes2) {

  $gene->analysis($analysis);

  $db->get_GeneAdaptor->attach_to_Slice($gene,$slice);

  foreach my $tran (@{$gene->get_all_Transcripts}) {
    foreach my $exon (@{$tran->get_all_Exons}) {
    print "Exon **** " . $exon->stable_id . " " . $exon->start . "\t" . $exon->end . "\t" . $exon->strand . "\t" . $exon->phase . "\t"
. $exon->end_phase. "\n";
    }
    if (defined($tran->translation)) {
      print "Pre tran " . $tran->translate->seq . "\n";
      $transeq{$tran->stable_id} = $tran->translate->seq;
    }
  }
  $db->get_GeneAdaptor->store($gene);

}

print "Chr $chr $chrstart $chrend $type " . length($dna) . "\n";

ok($db->assembly_type($type));

#DBI->trace(2);
my $db3 = new Bio::Otter::DBSQL::DBAdaptor(-host => $otter_test->host,
                                           -user => $otter_test->user,
                                           -port => $otter_test->port,
                                           -dbname => $otter_test->dbname);

$db3->assembly_type($type);

my $slice3 = $db3->get_SliceAdaptor->fetch_by_chr_start_end($chr,$chrstart,$chrend);

ok($dna eq $slice3->seq);
my @genes = @{$db3->get_GeneAdaptor->fetch_by_Slice($slice)};
#$otter_test->pause;

print "PRE**************\n";
ok(my $str = Bio::Otter::Converter::otter_to_ace($slice,\@genes,$db->assembly_type));
print "POS**************\n";

open(OUT,">test.ace");
print OUT $str;
close(OUT);


open(IN,"<test.ace");

my ($genes,$frags,$path,$dna3,$chr3,$start,$end) = Bio::Otter::Converter::ace_to_otter(\*IN);


open(OUT2,">test.xml");

my $str2 = Bio::Otter::Converter::frags_to_XML($frags,$path,$chr3,$start,$end);
print OUT2 $str2 . "\n";

@$genes = sort {$a->gene_info->name cmp $b->gene_info->name} @$genes;

foreach my $gene (@$genes) {
    print OUT2 $gene->toXMLString . "\n";
}
close OUT2;

print "dna length " . length($dna) . "\n";
 
