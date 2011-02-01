use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan tests => 14;}

use Bio::Otter::GeneInfo;
use Bio::Otter::GeneRemark;
use Bio::Otter::Author;
use Bio::Otter::GeneName;
use Bio::Otter::GeneSynonym;

ok(1);

my $author1 = new Bio::Otter::Author(-name => 'michele',
				     -email => 'michele@sanger.ac.uk');


my $name = new Bio::Otter::GeneName(-name => 'poggene');


ok(1);

my $remark1 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the first remark");
my $remark2 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the second remark");
my $remark3 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the third remark");
my $remark4 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the fourth remark");
my $remark5 = new Bio::Otter::GeneRemark(-gene_info_id   => 1,
					 -remark         => "This is the fifth remark");


my $syn1 = new Bio::Otter::GeneSynonym(-name => 'pog1');
my $syn2 = new Bio::Otter::GeneSynonym(-name => 'pog2');
my $syn3 = new Bio::Otter::GeneSynonym(-name => 'pog3');

my $syn = [$syn1,$syn2,$syn3];

my $geneinfo = new Bio::Otter::GeneInfo(-gene_stable_id  => 'ENSG00000023222',
					-author          => $author1,
					-name            => $name,
					-synonym         => $syn,
					-remark          => [$remark1,$remark2]);

ok($geneinfo);

ok($geneinfo->gene_stable_id eq 'ENSG00000023222');
ok($geneinfo->author);
ok($geneinfo->author->name eq 'michele');
ok($geneinfo->author->email eq 'michele@sanger.ac.uk');
ok($geneinfo->name->name eq 'poggene');

ok(scalar($geneinfo->synonym) == 3);

my @remark = $geneinfo->remark;

ok(scalar(@remark) == 2);

$geneinfo->remark($remark3);

ok(scalar($geneinfo->remark) == 3);

my @remark2 = ($remark4,$remark5);

$geneinfo->remark(@remark2);

ok(scalar($geneinfo->remark) == 5);

print $geneinfo->toString() . "\n";

ok(1);

ok($geneinfo->equals($geneinfo));

