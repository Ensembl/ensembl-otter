
use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 13;}

use Bio::Otter::GeneRemark;

ok(1);

my $remark =  new Bio::Otter::GeneRemark(-dbid => 1,
                                         -remark => "this is a remark",
                                         -gene_info_id => 2);

my $remark1 =  new Bio::Otter::GeneRemark(-dbid => 2,
					  -remark => "this is another remark",
					  -gene_info_id => 2);

ok($remark);

ok($remark->dbID == 1);
ok($remark->remark eq "this is a remark");
ok($remark->gene_info_id == 2);


ok($remark->dbID(2));
ok($remark->dbID == 2);

ok($remark->remark("New remark"));
ok($remark->remark eq "New remark");
ok($remark->gene_info_id(3));
ok($remark->gene_info_id == 3);

ok($remark->equals($remark));
ok($remark->equals($remark1) == 0);

