
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 6;}

use Bio::Otter::TranscriptClass;


my $name1 = "CDS";
my $name2 = "Known";

my $desc = "Protein coding gene";

my $obj = new Bio::Otter::TranscriptClass(-name => $name1,
					  -dbID => 1,
					  -description => $desc);

my $obj2 = new Bio::Otter::TranscriptClass(-name => $name2,
					  -dbID => 2,
					  -description => $desc);

ok(1);

ok($obj->name eq "CDS");
ok($obj->description eq $desc);
ok($obj->dbID == 1);
ok($obj->equals($obj));
ok($obj->equals($obj2) == 0);
