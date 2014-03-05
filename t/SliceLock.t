#! /usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Try::Tiny;

use Test::Otter qw( ^db_or_skipall get_BOLDatasets get_BOSDatasets );
use Bio::Vega::ContigLockBroker;
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Author;

sub try_err(&) {
    my ($code) = @_;
    return try { $code->() } catch { "ERR:$_" };
}

sub main {
    plan tests => 3;

    # Test supportedness with B:O:L:Dataset + raw $dbh
    #
    # During feature branch, assume it is present on human_dev but not
    # human_test
    subtest supported_live => sub {
        supported_tt(human_test => [qw[ old ]]);
    };
    subtest supported_dev => sub {
        supported_tt(human_dev => [qw[ old new ]]);
    };

    # Exercise it
    subtest exercise_dev => sub {
        my ($ds) = get_BOLDatasets('human_dev');
        exercise_tt($ds);
    };

    return 0;
}

sub supported_tt {
    my ($dataset_name, $expect) = @_;
    my ($ds) = get_BOLDatasets($dataset_name);

    plan tests => 3;
    is_deeply(_support_which($ds), $expect, "BOLD:$dataset_name: support [@$expect]");

    # Test with a $dbh, and on non-locking schema
    my $p_dba = $ds->get_pipeline_DBAdaptor; # no sequence-locking of any sort
    is_deeply(_support_which($p_dba->dbc->db_handle),
              [], # none
              'unsupported @ pipedb');

    # Test with B:O:S:Dataset
    my ($ds2) = get_BOSDatasets($dataset_name);
    is_deeply(_support_which($ds2), $expect, "BOSD:$dataset_name: support [@$expect]");

    return;
}


sub _tidy_database {
    my ($dba) = @_;
    my $dbh = $dba->dbc->db_handle;
    $dbh->do(q{delete from slice_lock where hostname          = 'test.nowhere'});
    $dbh->do(q{delete from author     where author_email like '%@test.nowhere'});
    return;
}


sub exercise_tt {
    my ($ds) = @_;
    plan tests => 13;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    _tidy_database($SLdba);

    my @author = map {
        Bio::Vega::Author->new(-EMAIL => "\l$_\@test.nowhere",
                               -NAME => "$_ the Tester");
    } qw( Alice Bob );

    my %prop =
      (-SEQ_REGION_ID => int(rand(10000)), # may not exist
       -SEQ_REGION_START =>  10000 + int(rand(200000)),
       -SEQ_REGION_END   => 100000 + int(rand(150000)),
       -AUTHOR => $author[0], # to be created on store
       -ACTIVE => 'pre',
       -INTENT => 'testing',
       -HOSTNAME => 'test.nowhere');

    my $BVSL = 'Bio::Vega::SliceLock';

    # Instantiation fails
    my $no_dbID = try_err { $BVSL->new(-ADAPTOR => $SLdba, %prop) };
    like($no_dbID, qr{Cannot instantiate SliceLock},
         "reject new with only -ADAPTOR");
    my $no_adap = try_err { $BVSL->new(-DBID => 51463, %prop) };
    like($no_adap, qr{Cannot instantiate SliceLock},
         "reject new with only -DBID");

    # Make & store
    my $stored = $BVSL->new(%prop);
    isa_ok($stored, $BVSL, 'instantiate');
    ok( ! $stored->is_stored($SLdba->dbc), 'stored: not yet');
    $SLdba->store($stored);
    ok(   $stored->is_stored($SLdba->dbc), 'stored: it is now');

    # Find by unsaved author
    is($author[1]->dbID, undef, 'Bob: no dbID');
    my $unfind = try_err { $SLdba->fetch_by_author($author[1]) };
    isnt($author[1]->dbID, undef, 'Bob: dbID now');
    is_deeply($unfind, [], 'Bob: nothing found');

    # Find & compare
    my @found = try_err { @{ $SLdba->fetch_by_author($author[0]) } };
  SKIP: {
        unless (isa_ok($found[0], $BVSL, "find by author")) {
            diag explain({ found => \@found });
            skip 'need a lock object', 4;
        }
        is(scalar @found, 1, '  find: just one');
        my ($found) = @found;
        ok($found->is_stored($SLdba->dbc), '  find: is stored');
        is($found->dbID, $stored->dbID, '  find: is same lock row');
        is_deeply($found, $stored, '  find: is deeply same');
    }

    _tidy_database($SLdba);
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
        Bio::Vega::SliceLockBroker->supported($thing) ? ('new') : (),
      } catch {
          ("new:ERR:$_");
      };
    return \@out;
}


exit main();
