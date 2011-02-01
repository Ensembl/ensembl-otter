
use lib 't';
use strict;
use Test;

BEGIN { $| = 1; plan tests => 7 }

use Bio::Otter::GeneSynonym;

ok(1);

my $obj = new Bio::Otter::GeneSynonym(-name         => 'poggy',
				   -dbID         => 1,
				   -gene_info_id => 1);

ok($obj);
ok($obj->name eq "poggy");
ok($obj->dbID         == 1);
ok($obj->gene_info_id ==1);
ok($obj->toString());
ok($obj->equals($obj));
