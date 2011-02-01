
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 18;}

use OtterTestDB;

use Bio::Otter::DBSQL::TranscriptRemarkAdaptor;
use Bio::Otter::TranscriptRemark;

ok(1);

my $otter_test = OtterTestDB->new;

ok($otter_test);

my $db = $otter_test->get_DBSQL_Obj;

ok($db);

my $adaptor = $db->get_TranscriptRemarkAdaptor();

ok($adaptor);


my $remark1 =  new Bio::Otter::TranscriptRemark(
					  -remark => "this is a remark",
					  -transcript_info_id => 2);
my $remark2 =  new Bio::Otter::TranscriptRemark(
					  -remark => "this is a second remark",
					  -transcript_info_id => 2);

my $remark3 =  new Bio::Otter::TranscriptRemark(
					  -remark => "this is a third remark",
					  -transcript_info_id => 3);
my $remark4 =  new Bio::Otter::TranscriptRemark(
					  -remark => "this is a fourth remark",
					  -transcript_info_id => 4);


my @remarks = ($remark1,$remark2);

ok($adaptor->store(@remarks));
ok($adaptor->store($remark3));
ok($adaptor->store($remark4));

my @newrem = $adaptor->list_by_transcript_info_id(2);

ok(scalar(@newrem) == 2);

foreach my $rem (@newrem) {
    ok($rem->transcript_info_id == 2);
    ok($rem->dbID);
    ok($rem->remark ne "");
}
	
my @rem = $adaptor->list_by_transcript_info_id(3);

ok(scalar(@rem) == 1);

my $rem = $rem[0];

ok($rem->dbID);
ok($rem->transcript_info_id == 3);
ok($rem->remark eq "this is a third remark");

