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
ok(my ($genes,$slice,$seq,$tile) = Bio::Otter::Converter::XML_to_otter(\*IN,$db));

#ok(my ($genes2,$clones,$chr,$chrstart,$chrend,$type,$dna) = Bio::Otter::Converter::XML_to_otter(\*IN,$db));

#$otter_test->pause;

close(IN);

ok(open(IN,"<$file"));
my $oldxml = "";
while (<IN>) {
  $oldxml .= $_;
}
close(IN);

ok($db->assembly_type($slice->assembly_type));

my @contigs = @{$db->get_RawContigAdaptor->fetch_all};

#DBI->trace(2);

my $db2 = new Bio::Otter::DBSQL::DBAdaptor(-host => $otter_test->host,
                                           -user => $otter_test->user,
                                           -port => $otter_test->port,
                                           -dbname => $otter_test->dbname);

$db2->assembly_type($type);

my $slice = $db2->get_SliceAdaptor->fetch_by_chr_start_end($chr,$chrstart,$chrend);

ok($dna eq $slice->seq);


my $analysis = new Bio::EnsEMBL::Analysis(-logic_name => 'otter');
$db->get_AnalysisAdaptor->store($analysis);

my %transeq;

foreach my $gene (@$genes2) {
  
  $gene->analysis($analysis);

  $db->get_AnnotatedGeneAdaptor->attach_to_Slice($gene,$slice);

  foreach my $tran (@{$gene->get_all_Transcripts}) {
    if (defined($tran->translation)) {
      print "Pre tran " . $tran->translate->seq . "\n";
      $transeq{$tran->stable_id} = $tran->translate->seq;
    }
  }
  $db->get_AnnotatedGeneAdaptor->store($gene);

}

my @newgenes = @{$db->get_GeneAdaptor->fetch_all_by_Slice($slice)};

foreach my $gene (@newgenes) {
  foreach my $tran (@{$gene->get_all_Transcripts}) {

    if (defined($tran->translation)) {
      print "Translate " . $tran->translate->seq . "\n";
    }
  }
  foreach my $tran (@{$gene->get_all_Transcripts}) {

    if (defined($tran->translation)) {
      if ($transeq{$tran->stable_id} eq $tran->translate->seq) {
	print "OK      " . $tran->stable_id . "\n";
      } else {
	print "ERROR   " . $tran->stable_id . "\n";
      }
    }
  }
}
print ("Length dna " . length($dna) . " " . length($slice->seq) . "\n");

#my $xml   = Bio::Otter::Converter::path_to_XML($chr,$chrstart,$chrend,$type,@{$slice->get_tiling_path});
my $xml   = Bio::Otter::Converter::slice_to_XML($slice,$db,1);


my @genes = 
open OUT,">../data/test_db.xml.real";

print OUT $xml . "\n";

close(OUT);


#$otter_test->pause;


