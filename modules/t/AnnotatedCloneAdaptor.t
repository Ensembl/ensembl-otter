
use lib 't';
use strict;
use Test;

BEGIN { $| = 1; plan tests => 11 }

use OtterTestDB;
use Bio::Otter::AnnotatedClone;
use Bio::Otter::DBSQL::AnnotatedCloneAdaptor;
use Bio::Otter::CloneInfo;
use Bio::Otter::CloneRemark;
use Bio::Otter::Keyword;
use Bio::Otter::Author;

use Bio::SeqIO;

use Bio::EnsEMBL::Clone;
use Bio::EnsEMBL::RawContig;

ok(1);

my $testdb = OtterTestDB->new;

ok($testdb);

my $db = $testdb->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_AnnotatedCloneAdaptor;

ok($adaptor);


ok(3);

my $author = new Bio::Otter::Author(-name =>  'michele',
                                    -email => 'michele@sanger.ac.uk');

print "Auth " . $author->name . " " . $author->email . "\n";

ok(4);

my $remark1 = new Bio::Otter::CloneRemark(-remark => "This is the first remark");
my $remark2 = new Bio::Otter::CloneRemark(-remark => "This is the second remark");

my @remarks = ($remark1,$remark2);

ok(5);

my $keyword1 = new Bio::Otter::Keyword(-name => "keyword 1");
my $keyword2 = new Bio::Otter::Keyword(-name => "keyword 2");

my @keywords = ($keyword1,$keyword2);

my $cloneinfo = new Bio::Otter::CloneInfo(-clone_id  => 1,
                                          -author    => $author,
                                          -timestamp => 100,
                                          -is_active => 1,
                                          -remark    => \@remarks,
                                          -keyword   => \@keywords,
                                          -source    => 'SANGER');


ok(6);

my $fastafile = "../data/test_seq.fa";

if (-e $fastafile) {
  ok(7);
} 

open(IN,"<$fastafile") || die "can't open fasta file [$fastafile]\n";;

my $seqio = new Bio::SeqIO(-fh => \*IN, -format => 'fasta');

ok(8);

my $time  = time;
my $start = 1;
my $chunk = 200000;

while (my $seq = $seqio->next_seq) {

  my @seqs;

  if ($seq->length > $chunk) {
     @seqs = split_fasta($seq,$chunk);
  } else {
     @seqs = ($seq);
  }

  foreach my $tmpseq (@seqs) {

    # Create clone

    my $clone = new Bio::Otter::AnnotatedClone();
    $clone->id($tmpseq->id);
    $clone->embl_id($tmpseq->id);
    $clone->version(1);
    $clone->embl_version(1);
    $clone->htg_phase(-1);
    $clone->created($time);
    $clone->modified($time);

    # Create contig

    my $contig = new Bio::EnsEMBL::RawContig;

    $contig->name($tmpseq->id);
    $contig->clone($clone);
    $contig->embl_offset(1);
    $contig->length($tmpseq->length);
    $contig->seq($tmpseq->seq);

    $clone->add_Contig($contig);
    $clone->clone_info($cloneinfo);
    $db->get_AnnotatedCloneAdaptor->store($clone);


    my $newclone = $db->get_AnnotatedCloneAdaptor->fetch_by_accession_version($tmpseq->id,1);

    my $cloneinfo = $newclone->clone_info;

    my @contigs = @{$newclone->get_all_Contigs};

    #$testdb->pause;
  }
}
ok(9);


