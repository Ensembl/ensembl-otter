
use lib 't';
use strict;
use Test;

BEGIN { $| = 1; plan tests => 7 }

use Bio::Otter::Evidence;

my $obj = new Bio::Otter::Evidence(-dbID           => 1,
                                   -name           => 'AC053982',
				   -transcript_info_id  => 2,
				   -type           => 'EST');

my $obj2 = new Bio::Otter::Evidence(-dbID           => 1,
                                   -name           => 'AC053983',
				   -transcript_info_id  => 2,
				   -type           => 'EST');

ok($obj);
ok($obj->name eq 'AC053982');
ok($obj->transcript_info_id == 2);
ok($obj->dbID == 1);
ok($obj->type eq 'EST');
ok($obj->equals($obj));
ok($obj->equals($obj2) == 0);

