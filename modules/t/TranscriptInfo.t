
use lib 't';
use strict;

use Test;

BEGIN { $| = 1; plan tests => 22 }


use Bio::Otter::TranscriptInfo;
use Bio::Otter::TranscriptClass;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::Evidence;
use Bio::Otter::Author;


ok(1);

my $class = new Bio::Otter::TranscriptClass(-name => 'CDS',
					    -description => 'Protein coding gene');

ok($class);

my $author = new Bio::Otter::Author(-name => 'ewan',
				    -email => 'birney@ebi.ac.uk');

ok($author);

my $remark1 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk1");
my $remark2 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk2");
my $remark3 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk3");
my $remark4 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk4");
my $remark5 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk5");

my @remarks = ($remark1,$remark2);


ok(3);

my $ti = Bio::Otter::TranscriptInfo->new(
	-dbid => 2,
	-stable_id => 'yadda',
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 0,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 0,
	-author => $author,
	-remark => [$remark4,$remark5]);

ok($ti);

$ti->remark(@remarks);
$ti->remark($remark3);

my $ev1 = new Bio::Otter::Evidence(-name           => 'pog',
                                   -dbID           => 1,
                                   -transcript_id  => 2,
                                   -xref_id        => 3,
                                   -type           => 'EST');

my $ev2 = new Bio::Otter::Evidence(-name           => 'pog',
                                   -dbID           => 2,
                                   -transcript_id  => 2,
                                   -xref_id        => 3,
                                   -type           => 'EST');

my $ev3 = new Bio::Otter::Evidence(-name           => 'pog',
                                   -dbID           => 3,
                                   -transcript_id  => 2,
                                   -xref_id        => 3,
                                   -type           => 'EST');

ok($ti->add_Evidence($ev1));

my @ev = ($ev2,$ev3);

ok($ti->add_Evidence(@ev));

my @newev = @{$ti->get_all_Evidence};

ok(scalar(@newev) == 3);

ok($ti->name eq 'name');
ok($ti->cds_start_not_found == 1);
ok($ti->transcript_stable_id eq 'yadda');
ok($ti->cds_start_not_found ==1);
ok($ti->cds_end_not_found ==0);
ok($ti->mRNA_start_not_found ==1);
ok($ti->mRNA_end_not_found ==0);
ok($ti->class);
ok($ti->class->name eq "CDS");
ok($ti->class->description);
ok($ti->author);
ok($ti->author->name eq 'ewan');
ok($ti->author->email eq 'birney@ebi.ac.uk');

print $ti->toString . "\n";

ok($ti->equals($ti));
