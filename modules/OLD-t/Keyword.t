
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 12;}

use Bio::Otter::Keyword;

ok(1);

my $keyword = new Bio::Otter::Keyword(-name               => 'CpG island',
				      -dbID               => 1,
				      clone_info_id       => 2);


ok($keyword->name eq 'CpG island');
ok($keyword->dbID          == 1);
ok($keyword->clone_info_id == 2);

ok (print $keyword->toString . "\n");

ok($keyword->name('CpG'));
ok($keyword->clone_info_id(4));
ok($keyword->dbID(5));

ok($keyword->name eq 'CpG');
ok($keyword->dbID == 5);
ok($keyword->clone_info_id == 4);

ok(print $keyword->toString . "\n");

