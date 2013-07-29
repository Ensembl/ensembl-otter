# Parameters for a test region on human_test

package OtterTest::TestRegion;

use strict;
use warnings;

use Bio::Otter::LocalServer;

use Exporter qw( import );
our @EXPORT_OK = qw( %test_region_params );

our %test_region_params = (   ## no critic (Variables::ProhibitPackageVars)
    dataset => 'human_test',
    name    => '6',
    type    => 'chr6-18',
    cs      => 'chromosome',
    csver   => 'Otter',
    start   => 2864371,
    end     => 3037940,
    );

sub local_server {
    my $local_server = Bio::Otter::LocalServer->new;
    $local_server->set_params(%test_region_params);
    return $local_server;
}

1;
