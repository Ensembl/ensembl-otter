
use lib 't';

use strict;
use Test;

BEGIN { $| = 1; plan tests => 19 }

use OtterTestDB;

use Bio::Otter::DBSQL::AnnotatedGeneAdaptor;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptClass;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::GeneInfo;
use Bio::Otter::GeneRemark;
use Bio::Otter::GeneName;
use Bio::Otter::GeneSynonym;
use Bio::Otter::Author;
use Bio::Otter::Evidence;

use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::RawContig;
use Bio::EnsEMBL::Clone;

my $time_now = time;

ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_AnnotatedGeneAdaptor;

ok($adaptor);


my $author = new Bio::Otter::Author(-name =>  'michele',
                                    -email => 'michele@sanger.ac.uk');


ok(5);

my $remark1 = new Bio::Otter::GeneRemark(-remark => "This is the first remark");
my $remark2 = new Bio::Otter::GeneRemark(-remark => "This is the second remark");

my @remarks = ($remark1,$remark2);

my $syn1 = new Bio::Otter::GeneSynonym(-name => 'pog1');
my $syn2 = new Bio::Otter::GeneSynonym(-name => 'pog2');
my $syn3 = new Bio::Otter::GeneSynonym(-name => 'pog3');

my $syn = [$syn1,$syn2,$syn3];


ok(6);

my $geneinfo = new Bio::Otter::GeneInfo(-gene_stable_id  => 'ENSG00000023222',
                                        -dbID            => 1,
					-author          => $author,
					-synonym         => $syn,
					-name            => new Bio::Otter::GeneName(-name => 'poggene'),
					-remark          => \@remarks,
					-timestamp       => 100);
ok(print $geneinfo->toString . "\n");

$testdb->do_sql_file("../data/tinyassembly.sql");

my   $contig = $adaptor->db->get_RawContigAdaptor->fetch_by_dbID(1);

my $exon1 = new Bio::EnsEMBL::Exon(-start => 10,
				   -end   => 20,
				   -strand => 1,
				   -phase  => 0,
				   -end_phase => 0);

my $exon2 = new Bio::EnsEMBL::Exon(-start => 30,
				   -end   => 40,
				   -phase => 0,
				   -end_phase => 0,
				   -strand => 1);

my $exon3 = new Bio::EnsEMBL::Exon(-start => 50,
				   -end   => 60,
				   -phase => 1,
				   -end_phase => 1,
				   -strand => 1);

my $exon4 = new Bio::EnsEMBL::Exon(-start => 100,
				   -end   => 120,
				   -phase => 2,
				   -end_phase => 2,
				   -strand => -1);

$exon1->contig($contig);
$exon2->contig($contig);
$exon3->contig($contig);
$exon4->contig($contig);

$exon1->stable_id("ENSE000000100001");
$exon1->version(1);
$exon1->created($time_now);
$exon1->modified($time_now);
$exon2->stable_id("ENSE000000100002");
$exon2->version(1);
$exon2->created($time_now);
$exon2->modified($time_now);
$exon3->stable_id("ENSE000000100003");
$exon3->version(1);
$exon3->created($time_now);
$exon3->modified($time_now);
$exon4->stable_id("ENSE000000100004");
$exon4->version(1);
$exon4->created($time_now);
$exon4->modified($time_now);

ok(8);

my $transcript1 = new Bio::Otter::AnnotatedTranscript;
my $transcript2 = new Bio::Otter::AnnotatedTranscript;

$transcript1->add_Exon($exon1);
$transcript1->add_Exon($exon2);
$transcript1->add_Exon($exon3);
$transcript2->add_Exon($exon4);

my $translation1 = new Bio::EnsEMBL::Translation;
my $translation2 = new Bio::EnsEMBL::Translation;

$translation1->start_Exon($exon1);
$translation1->start(1);
$translation1->version(1);
$translation1->end_Exon($exon3);
$translation1->end(11);
$transcript1->translation($translation1);


$translation2->start_Exon($exon4);
$translation2->start(1);
$translation2->version(1);
$translation2->end_Exon($exon4);
$translation2->end(20);
$transcript2->translation($translation2);

$transcript1->stable_id("ENST000000100001");
$transcript1->version(1);
$transcript2->stable_id("ENST000000100002");
$transcript2->version(1);

$translation1->stable_id("ENSP00000100001");
$translation2->stable_id("ENSP00000100002");

my $class = new Bio::Otter::TranscriptClass(
     -name => 'CDS',
     -description => 'Protein coding gene');

my $remark3 = new Bio::Otter::TranscriptRemark(-remark => "This is the third remark");
my $remark4 = new Bio::Otter::TranscriptRemark(-remark => "This is the fourth remark");

my @rem2 = ($remark3,$remark4);

my $ti1 = Bio::Otter::TranscriptInfo->new(
	-dbid => 2,
	-stable_id => $transcript1->stable_id,
        -timestamp => 100,
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 0,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 0,
	-author => $author,
	-remark => \@rem2);

my $ti2 = Bio::Otter::TranscriptInfo->new(
	-dbid => 2,
	-stable_id => $transcript2->stable_id,
        -timestamp => 100,
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 0,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 0,
	-author => $author,
	-remark => \@rem2);

my $ev = new Bio::Otter::Evidence(-name           => 'pog',
                                  -dbID           => 1,
                                  -transcript_info_id  => 2,
                                  -xref_id        => 3,
                                  -type           => 'EST');

$ti1->evidence($ev);
$ti2->evidence($ev);

$transcript1->transcript_info($ti1);
$transcript2->transcript_info($ti2);

ok(9);

my $gene = new Bio::Otter::AnnotatedGene(-info => $geneinfo);

$gene->stable_id("ENSG00000023222");
$gene->version(1);
$gene->created($time_now);
$gene->modified($time_now);
$gene->type('otter');

print "ID1 " . $gene->stable_id . "\n";
print "ID2 " . $geneinfo->gene_stable_id . "\n";
ok(10);

$gene->add_Transcript($transcript1);
$gene->add_Transcript($transcript2);

foreach my $trans (@{$gene->get_all_Transcripts}) {
  print "seq = " . $trans->seq->seq . " " . length($trans->seq->seq) . "\n";
}
my $analysis = new Bio::EnsEMBL::Analysis(-logic_name => 'gene');

$gene->analysis($analysis);

ok(11);
print "stable".  $gene->stable_id . "\n";
print $ti1->toString . "\n";
$adaptor->store($gene);
#$testdb->pause;
my $version = $gene->version;
$version++;
$gene->version($version);
foreach my $exon (@{$gene->get_all_Exons}) {
    my $ev = $exon->version;
    $ev++;
    $exon->version($ev);
    $exon->adaptor(undef);
}
foreach my $tran (@{$gene->get_all_Transcripts}) {
    my $version = $tran->version;
    $version++;
    $tran->version($version);

    if (defined($tran->translation)) {
       my $version = $tran->translation->version;
       $version++;
       $tran->translation->version($version);
    }
}
$adaptor->store($gene);
#$testdb->pause;
ok(12);


my $newgene = $adaptor->fetch_by_stable_id('ENSG00000023222');

ok(print $newgene->gene_info->toString . "\n");

ok($newgene->version(2));

#my $newgene = $adaptor->fetch_by_dbID($gene->dbID);

my @rems = $newgene->gene_info->remark;

foreach my $rem (@rems) {
    print $rem->gene_info_id . " " . $rem->remark . "\n";
}
print $newgene->gene_info->author->name . "\n";

foreach my $tran (@{$newgene->get_all_Transcripts}) {
    print "Transcript " . $tran->dbID . " " . $tran->stable_id . "\n";
    foreach my $exon (@{$tran->get_all_Exons}) {
	print "Exon " . $exon->stable_id . "\t" . $exon->dbID . "\t" . $exon->start . "\t" . $exon->end . "\t" . $exon->strand . "\t" . $exon->phase . "\t" . $exon->end_phase . "\n";
    }
}
ok(13);

print $newgene->toXMLString . "\n";

my $xmlstr1 = $newgene->toXMLString;


my $slice = $adaptor->db->get_SliceAdaptor->fetch_by_chr_start_end("CHR",5,115);
my $slice_genes = $adaptor->fetch_by_Slice($slice);

ok(scalar(@$slice_genes) == 1);

my $newgene2 = $slice_genes->[0];

my $xmlstr2 = $newgene2->toXMLString;

ok($xmlstr1 eq $xmlstr2);

$adaptor->db->assembly_type("test_assem");

my $slice2 = $adaptor->db->get_SliceAdaptor->fetch_by_chr_start_end("CHR",1,115);

#Increase version and store on other assembly

$version = $gene->version;
$version++;
$gene->version($version);
foreach my $exon (@{$gene->get_all_Exons}) {
    my $ev = $exon->version;
    $ev++;
    $exon->version($ev);
    $exon->adaptor(undef);
}
foreach my $tran (@{$gene->get_all_Transcripts}) {
    my $version = $tran->version;
    $version++;
    $tran->version($version);
    if (defined($tran->translation)) {
       my $version = $tran->translation->version;
       $version++;
       $tran->translation->version($version);
    }
}

$exon1->contig($slice2);
$exon2->contig($slice2);
$exon3->contig($slice2);
$exon4->contig($slice2);

$gene->transform;

$adaptor->store($gene);

my $slice3 = $adaptor->db->get_SliceAdaptor->fetch_by_chr_start_end("CHR",6,115);
my $slice_genes3 = $adaptor->fetch_by_Slice($slice3);

ok(scalar(@$slice_genes3) == 1);

#$testdb->pause;

my $newgene3 = $slice_genes3->[0];

my $xmlstr3 = $newgene3->toXMLString;

print $xmlstr3 . "\n";
foreach my $trans (@{$newgene3->get_all_Transcripts}) {
  print "seq = " . $trans->seq->seq . " " . length($trans->seq->seq) . "\n";
}
ok($xmlstr1 eq $xmlstr3);
