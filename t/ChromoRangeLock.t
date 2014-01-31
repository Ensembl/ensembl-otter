#! /usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Try::Tiny;

use Test::Otter qw( ^db_or_skipall get_BOLDatasets );
use Bio::Vega::ContigLockBroker;
use Bio::Vega::RangeLockBroker;

sub main {
    plan tests => 2;

    # Test supportedness with B:O:L:Dataset + raw $dbh
    subtest supported_live => sub {
        supported_tt([qw[ old ]], # which systems should be working
                     get_BOLDatasets('human_test'));
    };

    # Exercise it
    my ($ds) = get_BOLDatasets('human_dev');
    subtest supported_dev => sub {
        exercise_tt($ds);
    };

    return 0;
}

sub supported_tt {
    my ($expect, @ds) = @_;

    plan tests => 2 + @ds;
    foreach my $ds (@ds) {
        my $name = $ds->name;
        is_deeply(_support_which($ds), $expect, "$name: supported as expected");
    }

    # Test with a $dbh, and on non-locking schema
    my $p_dba = $ds[0]->get_pipeline_DBAdaptor; # no sort of locking here!
    is_deeply(_support_which($p_dba->dbc->db_handle),
              [], # none
              'unsupported @ pipedb');

    # Test with B:O:S:Dataset
    {
        local $TODO = 'not implemented';
        fail("check ->supported calls with B:O:S:Dataset");
    }

    return;
}


sub exercise_tt {
    my ($ds) = @_;
    plan tests => 1;

    my $name = $ds->name;
    is_deeply(_support_which($ds), [qw[ old new ]], "$name: support both");

    return;
}

sub _support_which {
    my ($thing) = @_;
    my @out;
    push @out, try {
        Bio::Vega::ContigLockBroker->supported($thing) ? ('old') : (),
      } catch {
          ("old:ERR:$_");
      };
    push @out, try {
        Bio::Vega::RangeLockBroker->supported($thing) ? ('new') : (),
      } catch {
          ("new:ERR:$_");
      };
    return \@out;
}


exit main();
