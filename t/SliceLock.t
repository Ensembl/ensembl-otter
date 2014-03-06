#! /usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Try::Tiny;

use Test::Otter qw( ^db_or_skipall get_BOLDatasets get_BOSDatasets );
use Bio::Vega::ContigLockBroker;
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Author;

my $TESTHOST = 'test.nowhere'; # an invalid hostname

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
    $dbh->do(qq{delete from slice_lock where hostname           = '$TESTHOST'});
    $dbh->do(qq{delete from author     where author_email like '%\@$TESTHOST'});
    return;
}


sub exercise_tt {
    my ($ds) = @_;
    plan tests => 40;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    _tidy_database($SLdba);

    my @author = map {
        Bio::Vega::Author->new(-EMAIL => "\l$_\@$TESTHOST",
                               -NAME => "$_ the Tester");
    } qw( Alice Bob );

    my %prop =
      (-SEQ_REGION_ID => int(rand(10000)), # may not exist
       -SEQ_REGION_START =>  10000 + int(rand(200000)),
       -SEQ_REGION_END   => 100000 + int(rand(150000)),
       -AUTHOR => $author[0], # to be created on store
       -ACTIVE => 'pre',
       -INTENT => 'testing',
       -HOSTNAME => $TESTHOST);

    my $BVSL = 'Bio::Vega::SliceLock';

    # Instantiation failures expected
    my @inst_fail =
      ([ adaptor__no_dbID => qr{Cannot instantiate SliceLock},
         [ -ADAPTOR => $SLdba ] ],
       [ dbID__no_adaptor => qr{Cannot instantiate SliceLock},
         [ -DBID => 51463 ] ],
       [ non_fresh => qr{Fresh SliceLock must have active=pre},
         [ -ACTIVE => 'held' ] ],
       [ pre__freed      => qr{Fresh SliceLock must not be freed},
         [ -FREED => 'finished' ] ],
       [ pre__ts_freed   => qr{Fresh SliceLock must not be freed},
         [ -TS_FREE => time() ] ],
       [ pre__freed_auth => qr{Fresh SliceLock must not be freed},
         [ -FREED_AUTHOR => $author[0] ] ],
       [ ts_set => qr{Fresh SliceLock must have null timestamps},
         [ -TS_BEGIN => time() ] ],
      );
    foreach my $case (@inst_fail) {
        my ($label, $fail_like, $add_prop) = @$case;
        my %p = (%prop, @$add_prop);
        my $made = try_err { $BVSL->new(%p) };
        like($made, $fail_like, "reject new: testcase $label");
    }

    # Make & store
    my $stored = $BVSL->new(%prop);
    isa_ok($stored, $BVSL, 'instantiate');
    ok( ! $stored->is_stored($SLdba->dbc), 'stored: not yet');
    $SLdba->store($stored);
    ok(   $stored->is_stored($SLdba->dbc), 'stored: it is now');

    # Find by unsaved author.  Author is saved, nothing is found.
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

    # Find other ways
    my $fbID = $SLdba->fetch_by_dbID($stored->dbID);
    is_deeply($fbID, $stored, 'fetch_by_dbID same');

    my $fbsr = $SLdba->fetch_by_seq_region_id($stored->seq_region_id);
    $fbsr = [ grep { $_->hostname eq $TESTHOST } @$fbsr ]; # exclude non-test locks
    is_deeply($fbsr, [ $stored ], 'fetch_by_seq_region_id');

    my $feba = $SLdba->fetch_by_author($author[0], 1);
    is_deeply($feba, [ $stored ], 'fetch_by_author(+extant)');

    # Poke ye not
    foreach my $field (qw( dbID adaptor )) {
        like(try_err { $stored->$field("new junk value") },
             qr{^MSG: $field is immutable}m, "$field: immutable");
    }
    foreach my $field (qw( seq_region_id seq_region_start seq_region_end author ts_begin ts_activity active freed freed_author intent hostname ts_free )) {
        like(try_err { $stored->$field("new junk value") },
             qr{^MSG: $field is frozen}m, "$field: frozen");
    }

    # How not to free it
    my @unlock_fail =
      ([ same_expire => qr{'expired' inappropriate for same-author unlock},
         $author[0], 'expired' ],
       [ diff_fin => qr{'finished' inappropriate for bob@.* acting on alice@.* lock},
         $author[1], 'finished' ],
       [ diff_dflt => qr{'finished' inappropriate for bob.*alice}, $author[1] ]);
    foreach my $case (@unlock_fail) {
        my ($label, $fail_like, @arg) = @$case;
        my $unlocked = try_err { $SLdba->unlock($stored, @arg) };
        like($unlocked, $fail_like, "unlock fail: case $label");
    }

    # Free it
    $SLdba->unlock($stored, $author[0]);
    my $fba   = $SLdba->fetch_by_author($author[0]);
    my $feba2 = $SLdba->fetch_by_author($author[0], 1);
    is_deeply($fba, [ $stored ], 'unlocked.  fetch_by_author again');
    is_deeply($feba, [ ], 'fetch_by_author(+extant): none');

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
