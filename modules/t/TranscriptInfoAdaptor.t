
use lib 't';

use strict;
use Test;

BEGIN { $| = 1; plan tests => 25 }

use OtterTestDB;

use Bio::Otter::DBSQL::TranscriptInfoAdaptor;
use Bio::Otter::TranscriptClass;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::Evidence;
use Bio::Otter::Author;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_TranscriptInfoAdaptor();

ok($adaptor);


my $class =  new Bio::Otter::TranscriptClass(-name => 'CDS',
                                            -description => 'protein coding gene');


ok($class);

my $author = new Bio::Otter::Author(-name => 'michele',
				    -email => 'michele@sanger.ac.uk');


ok($author);


my $remark1 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk1");
my $remark2 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk2");
my $remark3 = new Bio::Otter::TranscriptRemark(-remark => "Reamrk3");

my @remarks = ($remark1,$remark2,$remark3);


ok(3);


my $ti = Bio::Otter::TranscriptInfo->new(
	-dbid => 2,
	-stable_id => 'yadda',
	-name => 'name',
	-class => $class,
	-cds_start_not_found => 1,
	-cds_end_not_found => 1,
	-mrna_start_not_found => 1,
	-mrna_end_not_found => 1,
	-author => $author,
	-remark => \@remarks);

ok($ti);

my $ev1 = new Bio::Otter::Evidence(-name           => 'pog',
                                   -transcript_info_id  => 2,
                                   -type           => 'EST');
my $ev2 = new Bio::Otter::Evidence(-name           => 'pog2',
                                   -transcript_info_id  => 2,
                                   -type           => 'EST');

$ti->evidence($ev1);
$ti->evidence($ev2);

ok(scalar($ti->evidence) == 2);

$adaptor->store($ti);

ok(1);

my $newti = $adaptor->fetch_by_stable_id('yadda');

ok(scalar($newti->evidence) == 2);

ok($ti->name eq 'name');
ok($ti->cds_start_not_found == 1);
ok($ti->transcript_stable_id eq 'yadda');
ok($ti->cds_start_not_found ==1);
ok($ti->cds_end_not_found ==1);
ok($ti->mRNA_start_not_found ==1);
ok($ti->mRNA_end_not_found ==1);
ok($ti->class);
ok($ti->class->name eq "CDS");
ok($ti->class->description eq 'protein coding gene');
ok($ti->author);
ok($ti->author->name eq 'michele');
ok($ti->author->email eq 'michele@sanger.ac.uk');
ok($ti->equals($ti));
print $newti->toString(); 

