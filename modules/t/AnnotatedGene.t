
use lib 't';
use strict;
use Test;

BEGIN { $| = 1; plan tests => 9 }

use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptClass;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::GeneInfo;
use Bio::Otter::GeneName;
use Bio::Otter::GeneSynonym;
use Bio::Otter::GeneRemark;
use Bio::Otter::Author;
use Bio::Otter::Evidence;

use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Exon;
ok(1);

my $author = new Bio::Otter::Author(-name =>  'michele',
                                    -email => 'michele@sanger.ac.uk');

print "Auth " . $author->name . " " . $author->email . "\n";
ok(2);

my $remark1 = new Bio::Otter::GeneRemark(-remark => "This is the first remark");
my $remark2 = new Bio::Otter::GeneRemark(-remark => "This is the second remark");

my @remarks = ($remark1,$remark2);

my $syn1 = new Bio::Otter::GeneSynonym(-name => 'pog1');
my $syn2 = new Bio::Otter::GeneSynonym(-name => 'pog2');
my $syn3 = new Bio::Otter::GeneSynonym(-name => 'pog3');

my $syn = [$syn1,$syn2,$syn3];

ok(3);

my $geneinfo = new Bio::Otter::GeneInfo(-gene_stable_id  => 'ENSG00000023222',
                                        -dbID            => 1,
					-author          => $author,
					-name            => new Bio::Otter::GeneName(-name => 'poggene'),
					-synonym         => $syn,
					-remark          => \@remarks,
					-timestamp       => 100);
ok(4);

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

$exon1->stable_id("ENSE000000100001");
$exon2->stable_id("ENSE000000100002");
$exon3->stable_id("ENSE000000100003");
$exon4->stable_id("ENSE000000100004");

ok(8);

my $transcript1 = new Bio::Otter::AnnotatedTranscript;
my $transcript2 = new Bio::Otter::AnnotatedTranscript;

$transcript1->add_Exon($exon1);
$transcript1->add_Exon($exon2);
$transcript1->add_Exon($exon3);
$transcript2->add_Exon($exon4);

$transcript1->stable_id("ENST000000100001");
$transcript2->stable_id("ENST000000100002");

ok(5);

my $class = new Bio::Otter::TranscriptClass(
     -name => 'CDS',
     -description => 'Protein coding gene');

my $remark3 = new Bio::Otter::TranscriptRemark(-remark => "This is the third remark");
my $remark4 = new Bio::Otter::TranscriptRemark(-remark => "This is the fourth remark");

my @rem2 = ($remark3,$remark4);

my $ev = new Bio::Otter::Evidence(-name           => 'pog',
                                  -dbID           => 1,
                                  -transcript_info_id  => 2,
                                  -xref_id        => 3,
                                  -type           => 'EST');


my $ti1 = Bio::Otter::TranscriptInfo->new(
	-timestamp => 100,
	-dbid => 2,
	-stable_id => 'yadda',
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 0,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 0,
	-author => $author,
	-remark => \@rem2);

my $ti2 = Bio::Otter::TranscriptInfo->new(
	-timestamp => 100,
	-dbid => 2,
	-stable_id => 'yadda',
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 0,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 0,
	-author => $author,
	-remark => \@rem2);

$ti1->add_Evidence($ev);
$ti2->add_Evidence($ev);

$transcript1->transcript_info($ti1);
$transcript2->transcript_info($ti2);

ok(6);

my $gene = new Bio::Otter::AnnotatedGene(-info => $geneinfo);

ok(7);

$gene->add_Transcript($transcript1);
$gene->add_Transcript($transcript2);
$gene->stable_id("ENSG00000023222");

ok(8);
print $gene->toXMLString . "\n";


