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

  $db->get_AnnotatedGeneAdaptor->attach_to_Slice($gene,$slice);

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
  $db->get_AnnotatedGeneAdaptor->store($gene);

}

print "Chr $chr $chrstart $chrend $type " . length($dna) . "\n";

ok($db->assembly_type($type));

#DBI->trace(2);
my $db2 = new Bio::Otter::DBSQL::DBAdaptor(-host => $otter_test->host,
                                           -user => $otter_test->user,
                                           -port => $otter_test->port,
                                           -dbname => $otter_test->dbname);

$db2->assembly_type($type);

my $slice = $db2->get_SliceAdaptor->fetch_by_chr_start_end($chr,$chrstart,$chrend);

ok($dna eq $slice->seq);
my @genes = @{$db2->get_AnnotatedGeneAdaptor->fetch_by_Slice($slice)};
#$otter_test->pause;

print "PRE**************\n";
ok(my $str = Bio::Otter::Converter::otter_to_ace($slice,\@genes,$db->assembly_type));
print "POS**************\n";

open(OUT,">test.ace");
print OUT $str;
close(OUT);




