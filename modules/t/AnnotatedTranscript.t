
use lib 't';
use strict;
use Test;

BEGIN { $| = 1; plan tests => 6 }

use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptClass;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::Author;
use Bio::Otter::Evidence;

use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Exon;
ok(1);

my $author = new Bio::Otter::Author(-name =>  'michele',
                                    -email => 'michele@sanger.ac.uk');

print "Auth " . $author->name . " " . $author->email . "\n";

ok(2);

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

ok(3);

my $transcript1 = new Bio::Otter::AnnotatedTranscript;

$transcript1->add_Exon($exon1);
$transcript1->add_Exon($exon2);
$transcript1->add_Exon($exon3);

$transcript1->stable_id("ENST000000100001");

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

$ti1->evidence($ev);

$transcript1->transcript_info($ti1);

ok(6);

ok($transcript1->stable_id eq $transcript1->transcript_info->transcript_stable_id);

