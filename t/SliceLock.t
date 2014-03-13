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
    plan tests => 7;

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
    my ($ds) = get_BOLDatasets('human_dev');
    _tidy_database($ds);
    foreach my $sub (qw( exercise_tt pre_unlock_tt cycle_tt timestamps_tt )) {
        my $code = __PACKAGE__->can($sub) or die "can't find \&$sub";
        subtest $sub  => sub { $code->($ds) };
    }

    _tidy_database($ds) if Test::Builder->new->is_passing; # leave evidence of fail

local $TODO = 'not tested';
fail('untested cycle: lock. interrupted from elsewhere. unlock => exception, but freshened.');

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
    my ($dataset) = @_;
    my $dbh = $dataset->get_cached_DBAdaptor->dbc->db_handle;
    $dbh->do(qq{delete from slice_lock where hostname           = '$TESTHOST'});
    $dbh->do(qq{delete from author     where author_email like '%\@$TESTHOST'});
    diag "purged test rows from ".($dataset->name);
    return;
}

sub _test_author {
    my @fname = @_;
    return map {
        Bio::Vega::Author->new(-EMAIL => "\l$_\@$TESTHOST",
                               -NAME => "$_ the Tester");
    } @fname;
}


# Basic create-store-fetch-lock-unlock cycle
sub exercise_tt {
    my ($ds) = @_;
    plan tests => 64;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;

    my @author = _test_author(qw( Alice Bob ));

    my %prop =
      (-SEQ_REGION_ID => int(rand(10000)), # may not exist
       -SEQ_REGION_START =>  10_000 + int(rand(200_000)),
       -SEQ_REGION_END   => 210_000 + int(rand(150_000)),
       -AUTHOR => $author[0], # to be created on store
       -ACTIVE => 'pre',
       -INTENT => 'testing',
       -HOSTNAME => $TESTHOST);

    my $BVSL = 'Bio::Vega::SliceLock';

    # Make & store
    my $stored = $BVSL->new(%prop);
    isa_ok($stored, $BVSL, 'instantiate');
    ok( ! $stored->is_stored($SLdba->dbc), 'stored: not yet');
    $SLdba->store($stored);
    ok(   $stored->is_stored($SLdba->dbc), 'stored: it is now');

    my $slice = $stored->slice;
    cmp_ok($slice->start, '<', $slice->end, 'slice is forwards');
    my $weird = Bio::EnsEMBL::Slice->new_fast
      ({ %$slice, strand => 0, start => 1000, end => 999 });
    cmp_ok($weird->start, '>', $weird->end, 'weird slice is backwards');

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
       [ sr_dup => qr{with -SLICE and \(SEQ_REGION_},
         [ -SLICE => Bio::EnsEMBL::Slice->new_fast({ junk => 'invalid' }) ] ],
       [ sr_rev => qr{Slice \(start 1000 > end 999\)},
         [ -SEQ_REGION_START => 1000, -SEQ_REGION_END => 999 ] ],
       [ sr_rev_slice => qr{Slice \(start 1000 > end 999\)},
         [ -SLICE => $weird, -SEQ_REGION_ID => undef,
           -SEQ_REGION_START => undef, -SEQ_REGION_END => undef ] ],
      );
    foreach my $case (@inst_fail) {
        my ($label, $fail_like, $add_prop) = @$case;
        my %p = (%prop, @$add_prop);
        my $made = try_err { $BVSL->new(%p) };
        like($made, $fail_like, "reject new: testcase $label");
    }

    # Find by duff PK
    {
        my $bad_dbID = $stored->dbID + 1000; # assumption: monotonic, DB not very busy
        is($SLdba->fetch_by_dbID($bad_dbID), undef, 'fetch_by_dbID(badPK)');
    }

    # Find by unsaved author.  Author is saved, nothing is found.
    {
        is($author[1]->dbID, undef, 'Bob: no dbID');
        my $unfind = try_err { $SLdba->fetch_by_author($author[1]) };
        isnt($author[1]->dbID, undef, 'Bob: dbID now');
        is_deeply($unfind, [], 'Bob: nothing found');
    }

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
    {
        my $fbID = $SLdba->fetch_by_dbID($stored->dbID);
        is_deeply($fbID, $stored, 'fetch_by_dbID same');

        my $fbsr = $SLdba->fetch_by_seq_region_id($stored->seq_region_id);
        $fbsr = # exclude non-test locks
          [ grep { $_->hostname eq $TESTHOST } @$fbsr ];
        is_deeply($fbsr, [ $stored ], 'fetch_by_seq_region_id');

        my $feba = $SLdba->fetch_by_author($author[0], 1);
        is_deeply($feba, [ $stored ], 'fetch_by_author(+extant)');
    }

    # Poke ye not
    foreach my $field (qw( dbID adaptor )) {
        like(try_err { $stored->$field("new junk value") },
             qr{^MSG: $field is immutable}m, "$field: immutable");
    }
    foreach my $field ($stored->FIELDS) {
        like(try_err { $stored->$field("new junk value") },
             qr{^MSG: $field is frozen}m, "$field: frozen");
    }

    # How not to free it
    my @unlock_fail =
      ([ same_expire => qr{'expired' inappropriate for same-author unlock},
         $author[0], 'expired' ],
       [ toolate_int => qr{'too_late' inappropriate}, $author[1], 'too_late' ],
       [ diff_fin => qr{'finished' inappropriate for bob@.* acting on alice@.* lock},
         $author[1], 'finished' ],
       [ diff_dflt => qr{'finished' inappropriate for bob.*alice}, $author[1] ]);
    foreach my $case (@unlock_fail) {
        my ($label, $fail_like, @arg) = @$case;
        my $unlocked = try_err { $SLdba->unlock($stored, @arg) };
        like($unlocked, $fail_like, "unlock fail: case $label");
    }

    # Lock it.  active=pre --> active=held
    my $stored_copy = $SLdba->fetch_by_dbID($stored->dbID);
    my @debug;
    is(try_err { $SLdba->do_lock($stored, \@debug) && 'ok' }, 'ok', 'locked!')
      or diag explain { debug => \@debug };
    ok($stored->is_held, '...confirmed by state');

    # Check test assumptions - independent objects from fetch_by_dbID
    ok(!$stored_copy->is_held, 'stored_copy: do_lock does not affect a copy');
    ok($stored_copy->is_held_sync, 'stored_copy: lock held, seen after freshen');
    my $stored_obliv = $SLdba->fetch_by_dbID($stored->dbID);

    # Free it
    ok($SLdba->unlock($stored, $author[0]), 'unlock');
    ok(!$stored->is_held, 'unlock freshens');
    {
        my $fba   = $SLdba->fetch_by_author($author[0]);
        my $feba2 = $SLdba->fetch_by_author($author[0], 1);
        is_deeply($fba, [ $stored ], 'unlocked.  fetch_by_author again');
        is_deeply($feba2, [ ], 'fetch_by_author(+extant): none')
          or diag explain $feba2;
    }
    ok($stored_copy->is_held, 'copy before unlock: not freshened');

    # Can't double-free
    {
        # $stored is already free, and the in-memory copy knows that
        my $free2 = try_err { $SLdba->unlock($stored, $author[0]) };
        like($free2, qr{SliceLock dbID=\d+ is already free}, 'no wilful double-free');
    }
    {
        # $stored_copy is already free, but doesn't find out until the UPDATE
        my $free3 = try_err { $SLdba->unlock($stored_copy, $author[0]) };
        like($free3, qr{SliceLock dbID=\d+ was already free}, 'no async double-free');
        ok(!$stored_copy->is_held, 'async lock break is freshened');
    }

    # See is_held_sync do the freshen
    ok($stored_obliv->is_held, 'async lock-break: in-memory copy is oblivious')
      or diag explain $stored_obliv;
    ok(!$stored_obliv->is_held_sync, 'async lock-break: is_held_sync notices');

    # Rejection of junk objects
    my $junk = bless {}, 'Heffalump';
    foreach my $method (qw( store freshen do_lock unlock )) {
        like(try_err { $SLdba->$method($junk) },
             qr{MSG: $method\(.*: not a SliceLock object},
             "SLdba->$method: reject junk");
    }

    return;
}

# Store(active=pre),unlock - it can be done
sub pre_unlock_tt {
    my ($ds) = @_;
    plan tests => 17;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my ($auth) = _test_author(qw( Percy ));
    my %prop = (-SEQ_REGION_ID => 1, -SEQ_REGION_START => 1, -SEQ_REGION_END => 1000,
                -AUTHOR => $auth,
                -INTENT => 'unlock again',
                -HOSTNAME => $TESTHOST,
                -OTTER_VERSION => '81_slice_lock');

    my $pre = Bio::Vega::SliceLock->new(%prop);
    $SLdba->store($pre);
    is($pre->active, 'pre', 'active=pre');
    my $load = $SLdba->fetch_by_dbID($pre->dbID);

    $SLdba->unlock($pre, $auth);
    is($pre->active, 'free', 'freed');
    is($pre->freed, 'finished', 'freed type');

    # Field re-load (from before unlock)
    my @case = ([ dbID => $pre->dbID ],
                [ adaptor => $SLdba ],
                [ seq_region_id => 1 ],
                [ seq_region_start => 1 ],
                [ seq_region_end => 1000 ],
                [ author => $auth->dbID, 'dbID' ],
                [ intent => 'unlock again' ],
                [ active => 'pre' ],
                [ freed => undef ],
                [ freed_author => undef ],
                [ ts_free => undef ],
                [ hostname => $TESTHOST ],
                [ otter_version => '81_slice_lock' ]);

    foreach my $case (@case) {
        my ($field, $want_val, $refmethod) = @$case;
        my $got_val = $load->$field;
        $got_val = $got_val->$refmethod if $refmethod;
        is($got_val, $want_val, "field: $field");
    }

    my %untested;
    @untested{(qw( dbID adaptor ), $pre->FIELDS )} = ();
    delete @untested{( map { $_->[0] } @case )};
    my @untested = sort keys %untested;
    is("@untested", "ts_activity ts_begin", 'untested field reload');
    # timestamps are tested time timestamps_tt

    return;
}


# Store,lock,unlock - interaction with another SliceLock
sub cycle_tt {
    my ($ds) = @_;
    plan tests => 11;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my @author = _test_author(qw( Xavier Yuel Zebby ));
    my $BVSL = 'Bio::Vega::SliceLock';
    my @L_pos = (int(rand(10000)), # may not exist
                 10_000 + int(rand(200_000)), 210_000 + int(rand(150_000)));
    my @R_pos = ($L_pos[0], $L_pos[1] + 50_000, $L_pos[2] + 50_000);

    my $L_lock = $BVSL->new
      (-SEQ_REGION_ID => $L_pos[0],
       -SEQ_REGION_START => $L_pos[1],
       -SEQ_REGION_END   => $L_pos[2],
       -AUTHOR => $author[0],
       -ACTIVE => 'pre',
       -INTENT => 'testing: will gain',
       -HOSTNAME => $TESTHOST);

    like(try_err { $L_lock->slice }, qr{cannot make slice without adaptor},
         "too early to get slice");

    # slice from lock...
    $SLdba->store($L_lock);

    my $L_slice = $L_lock->slice;
    is_deeply({ id => $L_slice->adaptor->get_seq_region_id($L_slice),
                start => $L_slice->start, end => $L_slice->end },
              { id => $L_pos[0], start => $L_pos[1], end => $L_pos[2] },
              'slice matches L_lock')
      or diag explain { sl => $L_slice, L_lock => $L_lock };

    my $R_slice = $SLdba->db->get_SliceAdaptor->fetch_by_seq_region_id(@R_pos);

    # ...lock from slice
    my $R_lock = $BVSL->new
      (-SLICE => $R_slice,
       -AUTHOR => $author[2],
       # -ACTIVE : implicit
       -INTENT => 'testing: boinged off',
       -HOSTNAME => $TESTHOST);

    is_deeply({ id => $R_slice->adaptor->get_seq_region_id($R_slice),
                start => $R_slice->start, end => $R_slice->end },
              { id => $R_pos[0], start => $R_pos[1], end => $R_pos[2] },
              'slice matches R_lock')
      or diag explain { sl => $R_slice, R_lock => $R_lock };

    $SLdba->store($R_lock);
    my $R_lock_copy = $SLdba->fetch_by_dbID($R_lock->dbID);

    my %debug;

    # make L_lock "held"
    is(try_err { $SLdba->do_lock($L_lock, ($debug{L_do_lock} = [])) && 'ok' },
       'ok', 'Did lock left') or $debug{show}=1;
    is($L_lock->active, 'held', 'left: active=held') or $debug{show}=1;
    ok($L_lock->is_held, 'left: is_held') or $debug{show}=1;

    # check effect on overlapping R_lock
    $SLdba->freshen($R_lock_copy);
    is($R_lock->active, 'pre', 'right: not yet told') or $debug{show}=1;
    is($R_lock_copy->active, 'free', 'right: freed async') or $debug{show}=1;

    # try R_lock anyway
    is(try_err { $SLdba->do_lock($R_lock, ($debug{R_do_lock} = [])) || 'ok' },
       'ok', 'Did not lock right') or $debug{show} = 1;
    is($R_lock->active, 'free', 'right: active=free') or $debug{show} = 1;
    is($R_lock->freed, 'too_late', 'right: freed(too_late)') or $debug{show} = 1;

    diag explain { debug => \%debug } if $debug{show};

    return;
}


sub timestamps_tt {
    my ($ds) = @_;
    plan tests => 9;

    # Interlocking cases run to minimise test-time wallclock duration
    my @actions =
      (# label => [ ...steps... ], { field => expect }
       [ A => [qw[ create wait create ]], { ts_begin => 'incr' }
         # i.e. Timestamp increased when second active=pre is made
       ],
       [ B => [qw[ create wait lock ]], { ts_begin => 'same', ts_activity => 'incr' },
         # In do_lock, retain the ts_begin but bump ts_activity.
         # Generally "pre" phase is short.
       ],
       [ C => [qw[ create lock wait bump ]],
         { ts_begin => 'same', ts_activity => 'incr' },
         # The bump operation, recommended for use with COMMIT, moves
         # ts_begin only.
       ],
       [ D => [qw[ create lock wait unlock ]],
         { ts_begin => 'same',
           ts_free => 'huge', # "before" was undef so delta is huge
           ts_activity => 'same' }
       ]);

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my ($auth) = _test_author(qw( Terry ));
    my %step =
      (create => sub {
           my ($label, $lock_stack, $when) = @_;
           my $objnum = @$lock_stack;
           my $lock = Bio::Vega::SliceLock->new
             (-SEQ_REGION_ID => 1E6 + ord($label),
              -SEQ_REGION_START => 1000,
              -SEQ_REGION_END   => 2000,
              -AUTHOR => $auth,
              -INTENT => "timestamps_tt($label) $objnum",
              -HOSTNAME => $TESTHOST);
           $SLdba->store($lock);
           push @$lock_stack, $lock;
           return;
       }, lock => sub {
           my ($label, $lock_stack, $when) = @_;
           my $lock = $lock_stack->[-1];
           $SLdba->do_lock($lock);
           return;
       }, bump => sub {
           my ($label, $lock_stack, $when) = @_;
           my $lock = $lock_stack->[-1];
           $lock->bump_activity;
           return;
       }, unlock => sub {
           my ($label, $lock_stack, $when) = @_;
           my $lock = $lock_stack->[-1];
           $SLdba->unlock($lock, $auth);
           return;
       });

    my %product; # key = label, value = [ $before_times, $after_times ]
    # %$each_times are key = fieldname, value = timestamp; taken before+after "wait"

    # Do the actions, consuming all steps in the process
    foreach my $when (0, 1) { # 0 = before, 1 = after
        foreach my $case (@actions) {
            push @$case, [] unless $when;
            my ($label, $steps, $fieldset, $lock_stack) = @$case;
            while (@$steps) {
                my $step = shift @$steps;
                last if $step eq 'wait'; # next time
                my $code = $step{$step}
                  or die "Bad step name '$step' in label=$label";
                $code->($label, $lock_stack, $when);
            }
            fail("More 'wait' than \$when in label=$label") if @$steps && $when;
            foreach my $field (keys %$fieldset) {
                my $lock = $lock_stack->[-1];
                $product{$label}->[$when]->{$field} = $lock->$field;
            }
        }
        sleep 1 unless $when;
    }

    my %ts_diff; # key = label, value = { $fieldname => $seconds_delta }
    foreach my $case (@actions) {
        my ($label, $steps, $fieldset, $lock_stack) = @$case;
        my $info = $product{$label};
        foreach my $fieldname (keys %$fieldset) {
            my $got_num = $ts_diff{$label}->{$fieldname} =
              $info->[1]->{$fieldname} - ($info->[0]->{$fieldname} || 0);

            my $want = $fieldset->{$fieldname};
            my $got_txt;
            if    ($got_num  < 0) { $got_txt = 'decr' } # weird
            elsif ($got_num == 0) { $got_txt = 'same' }
            elsif ($got_num < 60) { $got_txt = 'incr' }
            elsif ($got_num > 1300_000_000) { $got_txt = 'huge' }
            else { $got_txt = 'weird' }

            is($got_txt, $want, "case $label: ts_diff($fieldname)=$got_num");
        }
    }

    # during unlock, ts_free is set and ts_activity is not bumped
    my $free_diff = $product{'D'}[1]{'ts_free'} - $product{'D'}[1]{'ts_activity'};
    cmp_ok($free_diff, '>', 0, 'D: ts_free > ts_activity');

#    diag explain { actions => \@actions, product => \%product, ts_diff => \%ts_diff };
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
