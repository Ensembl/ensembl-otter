#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";
use OtterTest::DB;

use Test::More;

my $test_db = OtterTest::DB->new_with_dataset_info(undef, 'human');

my $vega_dba = $test_db->vega_dba;
isa_ok($vega_dba, 'Bio::Vega::DBSQL::DBAdaptor');
my $daf_adaptor = $vega_dba->get_DnaAlignFeatureAdaptor;
isa_ok($daf_adaptor, 'Bio::EnsEMBL::DBSQL::DnaAlignFeatureAdaptor');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
