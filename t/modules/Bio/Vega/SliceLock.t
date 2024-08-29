#! /usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;
use Test::More;
use Test::Differences;
use Try::Tiny;
use List::Util 'shuffle';
use List::MoreUtils 'uniq';
use Time::HiRes qw( gettimeofday tv_interval usleep );
use Date::Format 'time2str';

use Test::Otter qw( ^db_or_skipall get_BOLDatasets get_BOSDatasets try_err );
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Author;
use Bio::Otter::Version;

my $TESTHOST = 'test.nowhere'; # an invalid hostname

my @TX_ISO =
my ($ISO_UNCO,          $ISO_COMM,   $ISO_REPEAT,       $ISO_SERI) = # to avoid typos
  ('READ-UNCOMMITTED', 'READ-COMMITTED', 'REPEATABLE-READ', 'SERIALIZABLE');


sub noise {
    my @arg = @_;
    diag @arg if
      (!$ENV{HARNESS_ACTIVE} ||   # stand-alone test
       $ENV{HARNESS_IS_VERBOSE}); # under "prove -v"
    return;
}


sub main {
    plan tests => 39;

    # Test supportedness with B:O:L:Dataset + raw $dbh
    #
    # contig_locks tables have now been removed.
    subtest supported_live => sub {
        supported_tt(human => [qw[ new ]]);
    };
    subtest supported_dev => sub {
        supported_tt(human_dev => [qw[ new ]]);
    };

    # Exercise it
    my ($ds) = get_BOLDatasets('human_dev');
    my $dbh = $ds->get_cached_DBAdaptor->dbc->db_handle;
    _late_commit_register($dbh);
    _tidy_database($ds);

    my $junk # warm the cache before tests start
      = _notlocked_seq_region_id($ds->get_cached_DBAdaptor);

    foreach my $iso ($ISO_UNCO, $ISO_COMM) {
        subtest "bad_isolation_tt($iso)" => sub { bad_isolation_tt($ds, $iso) };
    }

    my @tt = qw( exercise_tt pre_unlock_tt cycle_tt timestamps_tt two_conn_tt
                 describe_tt exclwork_tt contains_tt );
    foreach my $iso ($ISO_REPEAT, $ISO_SERI) {
        _iso_level($dbh, $iso); # commit!

        foreach my $sub (@tt) {
            my $code = __PACKAGE__->can($sub) or die "can't find \&$sub";
            is(_iso_level($dbh), $iso, "next test: $iso !")
              or die "hopeless - authors will collide";
            subtest "$sub(\L$iso)" => sub { $code->($ds) };
        }
    }

    subtest broker_tt => \&broker_tt;
    subtest fetch_by => sub { fetchby_tt($ds) };
    subtest json_tt  => sub { json_tt($ds) };

    _tidy_database($ds) if Test::Builder->new->is_passing; # leave evidence of fail

    return 0;
}


END {
    # If the test is aborting with an error, COMMIT the evidence
    _late_commit_do();
}
{
    my %dbh;
    sub _late_commit_register {
        my ($dbh) = @_;
        $dbh{$dbh} = $dbh;
        return;
    }

    sub _late_commit_do {
        while (my ($k, $dbh) = each %dbh) {
            if ($dbh && $dbh->ping) {
                if ($dbh->{AutoCommit}) {
                    noise "_late_commit_do: $dbh has no outstanding transaction";
                } else {
                    noise "_late_commit_do: $dbh->commit";
                    $dbh->commit;
                }
            } else {
                noise "_late_commit_do: $dbh: gone";
            }
        }
        return;
    }
}
# Useful query for dumping locks
#
# select l.slice_lock_id slid, l.seq_region_id srid, l.seq_region_start st, l.seq_region_end end, intent,hostname,otter_version, ts_begin,ts_activity,ts_free,active,freed,freed_author_id,author_id, a.author_name from slice_lock l join author a using (author_id);
#
# select cl.contig_lock_id CLid, cl.seq_region_id srid, sr.name, cl.hostname, cl.timestamp, cl.author_id, a.author_name, sl.slice_lock_id slid, sl.active, sl.freed, slr.name, slc.name from contig_lock cl natural join seq_region sr left join author a using (author_id) left join slice_lock sl on concat('SliceLock.', sl.slice_lock_id) = cl.hostname left join seq_region slr on slr.seq_region_id = sl.seq_region_id left join coord_system slc on slr.coord_system_id = slc.coord_system_id where cl.hostname like 'SliceLock%';


sub supported_tt {
    my ($dataset_name, $expect) = @_;
    my ($ds) = get_BOLDatasets($dataset_name);

    plan tests => 4;
    my $supported = _support_which($ds);
    is_deeply($supported, $expect, "BOLD:$dataset_name: support [@$expect]");

    # Test with a $dbh, and on non-locking schema
    my $p_dba = $ds->get_pipeline_DBAdaptor; # no sequence-locking of any sort
    is_deeply(_support_which($p_dba->dbc->db_handle),
              [], # none
              'unsupported @ pipedb');

    # Test with B:O:S:Dataset
    my ($ds2) = get_BOSDatasets($dataset_name);
    is_deeply(_support_which($ds2), $expect, "BOSD:$dataset_name: support [@$expect]");

  SKIP: {
        skip 'no slice_lock table', 1 unless grep { $_ eq 'new' } @$supported;
        my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
        eq_or_diff($SLdba->db_CREATE_TABLE(1),
                   $SLdba->pod_CREATE_TABLE(1),
                   'slice_lock schema check');
    };

    return;
}


sub _tidy_database {
    my ($dataset) = @_;
    my $dbh = $dataset->get_cached_DBAdaptor->dbc->db_handle;
    $dbh->do(qq{delete from slice_lock where hostname           = '$TESTHOST'});
    $dbh->do(qq{delete from author     where author_email like '%\@$TESTHOST'});
    noise "purged test rows from ".($dataset->name);
    return;
}

sub _test_author {
    my ($dba, @fname) = @_;

    my $uniqify = do {
        my $dbh = $dba->dbc->db_handle;
        my $tx_iso = _iso_level($dbh);
        $tx_iso =~ s{([A-Z])[A-Z]+(-|$)}{$1}g;
        my ($ptid) = $dbh->selectrow_array
          ('SELECT @@pseudo_thread_id'); # "This variable is for internal server use."
        "pt${ptid}p${$}i$tx_iso";
    };

    return map {
        Bio::Vega::Author->new(-EMAIL => "$uniqify,\l$_\@$TESTHOST", # varchar(50)
                               -NAME => "$_ the Tester ($uniqify)"); # varchar(50)
    } @fname;
}

# Pick a seq_region_id which is not locked, either valid OR somewhat
# far past anything locked so far, leaving room for those we can't see
# (not COMMITted elsewhere) etc.
#
# Beware that in SERIALIZABLE mode, SELECT will place Next-Key Locks.
# On slice_lock this can make spurious & confusing test failure.
#
# Therefore, list some nice ones at start of test and hand out each
# one once.
my %_notlocked_seq_region_id; # key = schema-name@hostname, value = \@shuffled
sub _notlocked_seq_region_id {
    my ($dba) = @_;
    my $dbh = $dba->dbc->db_handle;
    my ($db_name) = $dbh->selectrow_array(q{ SELECT database() });
    my $db_host = $dba->dbc->host;
    my $dbkey = "$db_name\@$db_host";

    my $srid_list = $_notlocked_seq_region_id{$dbkey};
    if (!defined $srid_list) {
        my $q = q{
      SELECT seq_region_id
      FROM seq_region r JOIN coord_system cs using (coord_system_id)
      WHERE r.seq_region_id not in (select seq_region_id from slice_lock)
        AND cs.name not in ('clone') -- they crowd the legacy contig_locks
        };
        $srid_list = $_notlocked_seq_region_id{$dbkey} = [];
        @$srid_list = shuffle @{ $dbh->selectcol_arrayref($q) };
    }

    my $val = pop @$srid_list;
    die "ran out of valid seq_region_id on dbkey=$dbkey" unless $val;
    return $val;
}


# Basic create-store-fetch-lock-unlock cycle
sub exercise_tt {
    my ($ds) = @_;
    plan tests => 69;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;

    my @author = _test_author($SLdba, qw( Alice Bob ));

    my %prop =
      (-SEQ_REGION_ID => _notlocked_seq_region_id($SLdba),
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
    like(try_err { $SLdba->do_lock($stored) },
         qr{MSG: do_lock: .* has not been stored}, 'stored:  cannot lock until it is');
    $SLdba->store($stored);
    ok(   $stored->is_stored($SLdba->dbc), 'stored:   it is now');

    my $slice = $stored->slice;
    cmp_ok($slice->start, '<', $slice->end, 'slice is forwards');
    my $weird = Bio::EnsEMBL::Slice->new_fast
      (+{ %$slice, strand => 0, start => 1000, end => 999 });
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
       [ sr_floats => qr{MSG: seq_region_id not set.*\n.*SliceLockAdaptor::store},
         [ -SEQ_REGION_ID => undef, # the failure happens in ->store
           -SEQ_REGION_START => 100, -SEQ_REGION_END => 200 ] ],
      );
    foreach my $case (@inst_fail) {
        my ($label, $fail_like, $add_prop) = @$case;
        my %p = (%prop, @$add_prop);
        my $made = try_err { my $L = $BVSL->new(%p); $SLdba->store($L); 'STORED' };
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
    noise 'author[0]="'.($author[0]->name).'" <'.($author[0]->email).'>';
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
      ([ toolate_int => qr{'too_late' inappropriate}, $author[1], 'too_late' ],
       [ diff_fin =>
         qr{'finished' inappropriate for .*,bob@.* acting on .*,alice@.* lock},
         $author[1], 'finished' ],
       [ diff_dflt => qr{'finished' inappropriate for .*,bob.*alice}, $author[1] ]);
    foreach my $case (@unlock_fail) {
        my ($label, $fail_like, @arg) = @$case;
        my $unlocked = try_err { $SLdba->unlock($stored, @arg) };
        like($unlocked, $fail_like, "unlock fail: case $label");
    }

    like(try_err { $stored->bump_activity },
         qr{ failed, rv=0E0 dbID=\d+ active=pre\b},
         'bump_activity(pre): fails');

    # Lock it.  active=pre --> active=held
    my $stored_copy = $SLdba->fetch_by_dbID($stored->dbID);
    my @debug;
    is(try_err { $SLdba->do_lock($stored, \@debug) && 'ok' }, 'ok', 'locked!')
      or diag explain { debug => \@debug };
    ok($stored->is_held, '...confirmed by state');
    is($stored->adaptor->bump_activity($stored), 1, 'bump_activity returncode');
    is($stored->bump_activity, 1, 'bump_activity returncode (convenience method)');
    # bump_activity effect is tested in timestamps_tt

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
    like(try_err { $stored->bump_activity },
         qr{ failed, rv=0E0 dbID=\d+ active=free\b},
         'bump_activity(free): fails');

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


sub _arbitrary_slice {
    my ($ds) = @_;
    my $slice = $ds->get_cached_DBAdaptor->get_SliceAdaptor->fetch_by_region
      (chromosome => 'chr1-14', 30_000, 230_000)
        or die "Can't get slice";
    return $slice;
}

sub describe_tt {
    my ($ds) = @_;
    plan tests => 21;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my $dbh = $SLdba->dbc->db_handle;
    my ($auth_des, $auth_bob) = _test_author($SLdba, qw( Desmond Bob ));
    my $slice_re = qr{chromosome:Otter(?:Archive)?:chr1-14:30000:230000:1};

    my @L;
    foreach my $i (0..3) {
        my $l = Bio::Vega::SliceLock->new
          (-SLICE => _arbitrary_slice($ds),
           -AUTHOR => $auth_des,
           -INTENT => "demonstrate describe method($i)",
           -HOSTNAME => $TESTHOST);
        $SLdba->store($l);

        # Pokery makes regular data with times in summer & winter
        $dbh->do
          (q{ UPDATE slice_lock SET
                ts_begin=from_unixtime(1218182888),
                ts_activity=from_unixtime(1321009871)
              WHERE slice_lock_id=? }, {}, $l->dbID);
        $SLdba->freshen($l);

        push @L, $l;
    }
    my ($L, $L_late, $L_expire, $L_int) = @L;

    my $ANYTIME_RE = qr{\b([-: 0-9]{19}) GMT\b};
    my $MAILDOM_RE = qr{\x40\Q$TESTHOST\E};
    my $BASE =
      qr{\ASliceLock\(dbID=\d+\)\ on\ $slice_re
         \Q was created 2008-08-08 08:08:08 GMT\E\n\Q  by\E
         \ \S*desmond$MAILDOM_RE\Q on host $TESTHOST\E\n\Q  to\E
         \Q "demonstrate describe method\E\(\d+\)"\.\n\Q  It\E
         \Q was last active \E$ANYTIME_RE\Q and now}x;
    my $LAST_ACT_2011_RE = qr{last active 2011-11-11 11:11:11 };

    like($L->describe, qr{$BASE 'pre'\n  The region is not yet locked\.\Z}, 'pre');
    like($L->describe, $LAST_ACT_2011_RE, 'pre ts_activity');
    like($L->describe_slice, $slice_re, 'pre describe_slice');
    like($L->describe_author, qr{^\S*desmond$MAILDOM_RE$}, 'pre describe_author');

    is($L_int->_author_id, $auth_des->dbID, '_author_id');
    is($L_int->_freed_author_id, undef, '_freed_author_id (pre)');

    $SLdba->unlock($L_expire, $auth_bob, 'expired');
    $SLdba->unlock($L_int,    $auth_bob, 'interrupted');
    $SLdba->do_lock($L);
    $SLdba->freshen($L_late);
    like($L->describe, qr{$BASE 'held'\n  The region is locked\.\Z}, 'held');
    unlike($L->describe, $LAST_ACT_2011_RE, 'held ts_activity bumped');

    $SLdba->unlock($L, $auth_des);
    my $now = time();
    my @now = map { time2str(' %R:', $_, 'GMT') }
      ($now-15, $now, $now+15); # " HH:MM:"
    my $now_re = join '|', uniq @now;
    $now_re = qr{\S+(?:$now_re)\d{2} GMT\b};
    like($L->describe,
         qr{$BASE 'free\(finished\)' since ($now_re)\n  The region was closed\.\Z},
         'free');

    like($L->describe('rollBACK'),
         qr{to "demonstrate describe method\(0\)"\.\n  Before rollBACK, it was last active },
         'free before rollback');
    $dbh->commit;
    is(try { $SLdba->freshen($L); 'present' }, 'present',
       'not actually rolled back');

    like($L_late->describe,
         qr{$BASE 'free\(too_late\)' since ($now_re)\n  Lost the race to lock the region\.\Z},
         'free(too_late)');
    like($L_expire->describe,
         qr{$BASE 'free\(expired\)' by \S*bob$MAILDOM_RE since ($now_re)\n  The lock was broken\.\Z},
         'free(expired)');
    like($L_int->describe,
         qr{$BASE 'free\(interrupted\)' by \S*bob$MAILDOM_RE since ($now_re)\n  The lock was broken\.\Z},
         'free(interrupted)');
    like($L_int->describe_freed_author, qr{^\S*bob$MAILDOM_RE$}, 'describe_freed_author (post)');
    is($L_int->_author_id, $auth_des->dbID, '_author_id');
    is($L_int->_freed_author_id, $auth_bob->dbID, '_freed_author_id (post)');

    # Test with non-stored, and bad slice
    my $bad = Bio::Vega::SliceLock->new
      (-SEQ_REGION_ID => _notlocked_seq_region_id($SLdba),
       -SEQ_REGION_START => 10,
       -SEQ_REGION_END => 100,
       -AUTHOR => $auth_des,
       -INTENT => "weird describe",
       -HOSTNAME => $TESTHOST);
    like(try_err { $bad->describe },
         qr{\A\QSliceLock(not stored) on \EBAD:srID=\d+:start=10:end=100
            \Q was created Tundef\E\n
            \Q  by \E\S*desmond$MAILDOM_RE\Q on host $TESTHOST\E\n
            \Q  to "weird describe".\E\n
            \Q  It was last active Tundef and now 'pre(new)'}x,
         'unsaved, bad slice');

    # Test with bogus author
    my $worse = bless { }, 'Bio::Vega::SliceLock';
    is($worse->describe_author, '<???>', 'invalid:describe_author');
    is($worse->describe_freed_author, undef, 'undef:describe_freed_author');
    $worse->{freed_author} = [];
    is($worse->describe_freed_author, '<???>', 'invalid:describe_freed_author');

    return;
}


sub exclwork_tt {
    my ($ds) = @_;
    plan tests => 6;

    local $SIG{__WARN__} = sub {
        my ($msg) = @_;
        # During the exclusive_work tests, we expect everything to
        # succeed with no hint of trouble.
        if ($msg =~ m{there is a difference in the software release \(\d+\) and the database release \(\d+\)}) {
            warn "[ ignored a warning ] $msg";
        } else {
            fail("warning seen: $msg");
        }
        return;
    };

    my $BVSLB = 'Bio::Vega::SliceLockBroker';
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my $dbh = $SLdba->dbc->db_handle;
    my ($auth) = _test_author($SLdba, qw( Florence ));
    my $srid = _notlocked_seq_region_id($SLdba);

    my @L;
    foreach my $i (0, 1) {
        push @L, Bio::Vega::SliceLock->new
          (-SEQ_REGION_ID => $srid,
           -SEQ_REGION_START => 10_000,
           -SEQ_REGION_END => 20_000,
           -AUTHOR => $auth,
           -INTENT => "workflow convenience method($i)",
           -HOSTNAME => $TESTHOST);
    }
    my ($L, $L_late) = @L; # two pre locks, same region
    my $L_time; # latest expected activity time for $L (local clock)

    my $fail_work = sub { fail("the work - should not happen yet") };
    my $pass_work = sub { ok(1, 'work is done') }; # part of the plan
    subtest adaptor_check => sub {
        plan tests => 6;
        is($L->adaptor, undef, 'L not stored');
        is($auth->adaptor, undef, 'author not stored');
        like(try_err { $BVSLB->new(-locks => $L)->exclusive_work($fail_work) },
             qr{MSG: adaptor not yet available}, 'unstored');

        $SLdba->store($L);
        is(try_err { $BVSLB->new(-locks => $L)->exclusive_work($pass_work) },
           undef, 'run with a pass');
        $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
        $dbh->rollback; # no effect due to earlier COMMITs
        is($L->is_held_sync, 1, 'lock still held');
    };

    is($L->can('exclusive_work'), undef,
       "locks don't exclusive_work"); # they did in early API

    subtest work_fail => sub {
        plan tests => 7;

        $SLdba->store($L_late);
        like(try_err { $BVSLB->new(-locks => $L_late)->exclusive_work($fail_work) },
             qr{\QCannot proceed, do_lock failed <lost the race\E[^>]*
                \Q> leaving SliceLock\E\(dbID=\d+\).*
                \Qand now 'free(too_late)'}sx,
             'cannot: lock attempt found to be too late');
        is($L_late->active, 'pre', 'L_late:pre (rolled back)');

        $SLdba->unlock($L_late, $auth);
        like(try_err { $BVSLB->new(-locks => $L_late)->exclusive_work($fail_work) },
             qr{Cannot proceed, not holding the lock SliceLock\(dbID=\d+\)},
             'cannot: not locked');

        # a feature which will be cached across the rollback
        my $SFdba = $SLdba->db->get_SimpleFeatureAdaptor;
        my ($any_ana) = @{ $SLdba->db->get_AnalysisAdaptor->fetch_all };
        my $sf = Bio::EnsEMBL::SimpleFeature->new
          (-start => 5, -end => 10, -strand => 1,
           -slice => $L->slice, -analysis => $any_ana,
           -score => 1.5E9, -display_label => 'SliceLock.t');

        my $slice_fetch = sub { # potentially cached
            my $fetch = $SFdba->fetch_all_by_Slice_and_score($L->slice, 1.0E9);
            my ($it) = grep { $_->dbID == $sf->dbID } @$fetch;
            return $it;
        };

        my $work_dies = sub {
            $SFdba->store($sf); # INSERT by SFdba
            my $sf_warmup = $slice_fetch->(); # warm up the cache in BaseFeatureAdaptor
            is(try_err { $sf_warmup->dbID }, $sf->dbID, 'fetcher does cache');
            isnt($sf->dbID, undef, 'SimpleFeature was stored');
            die "this work doesn't\n";
            # ROLLBACK by broker
        };

        # work fails, requested unlock doesn't happen
        like(try_err { $BVSLB->new(-locks => $L)->exclusive_work($work_dies, 1) },
             qr{^\QMSG: << SliceLock\E\(dbID=\d+\).*\Q and now 'held'\E.*
                \Q >> was held, but work failed <this work doesn't>\E}xms,
             'run with error');
        $L_time = [ gettimeofday() ];

        my $post_rollback_sf = $slice_fetch->();
        is_deeply($post_rollback_sf, undef, 'post-rollback clear_caches');
    };

    subtest no_exclusive_recurse => sub {
        plan tests => 3;
        my $br = $BVSLB->new(-locks => $L);
        my $br_empty = $BVSLB->new();
        my $fail_recurse_work = sub { fail("it did let me recurse") };
        my $err_re = qr{^ERR:.*MSG: exclusive_work recursion}s;
        my $bad_work = sub {
            ok(1, "bad_work started");
            # surely you wouldn't...?  but we are
            like(try_err { $br_empty->exclusive_work($fail_recurse_work) },
                 $err_re, 'recursion prevented (different object)');
            $br->exclusive_work($fail_recurse_work);
        };
        like(try_err { $br->exclusive_work($bad_work); 'done' },
             $err_re, 'recursion prevented (same object)');
    };

    subtest assert_bumped => sub {
        plan tests => 9;
        my $br = $BVSLB->new(-locks => $L);
        my $Sdba = $SLdba->db->get_SliceAdaptor;
        my @r = map { $Sdba->fetch_by_seq_region_id(@$_) || die "? (@$_)" }
          ( [ $srid, 15_000, 16_000 ],
            [ $srid, 16_000, 17_000 ],
            [ $srid, 23_000, 25_000 ],
            [ $srid, 10_000, 25_000 ] );

        like(try_err { $br->assert_bumped($r[0]) },
             qr{^ERR:.* only permitted during exclusive_work}s,
             'no assert_bumped outside exclusive_work');

        # nap until the next second (the SQL-remote second must tick)
        my $old_act = $L->iso8601_ts_activity;
        my $L_age = tv_interval($L_time) * 1E6;
        usleep(1E6 - $L_age) if $L_age < 1E6;

        my $ok_work = sub {
            cmp_ok($L->iso8601_ts_activity, 'gt', $old_act, 'bumped');
            is( $br->assert_bumped(@r[0, 1]), 1, '[0,1] => true');
            is( $br->assert_bumped(),         0, '[]    => false');
            like(try_err { $br->assert_bumped($r[2]) },
                 qr{^ERR:.* not \S* covered by any of my locks}s, '[2] => err');

            # adding another lock during work (not recommended)
            # does not include it in assert_bumped, in this call
            push @L, $br->lock_create_for_Slice
              (-seq_region_id => $srid,
               -seq_region_start => 20_001,
               -seq_region_end => 25_000,
               -intent => 'added in ok_work');
            like(try_err { $br->assert_bumped($r[2]) },
                 qr{^ERR:.* not \S* covered by any of my locks}s,
                 '[2] => err (after lock)');
        };
        $br->exclusive_work($ok_work);

        like(try_err { $br->assert_bumped($r[0]) },
             qr{^ERR:.* only permitted during exclusive_work}s,
             'no assert_bumped outside exclusive_work (after)');

        my $ok2_work = sub {
            is( $br->assert_bumped($r[2]), 1, '[2] => true (next work)');
            my $contiguous = try_err { $br->assert_bumped($r[3]) };
            local $TODO = 'YAGNI';
            $contiguous =~ s{.*^(MSG:.*?)\n.*}{$1}ms;
            like($contiguous, qr{^1$}s,
                 '[3] => true, contiguous region emulation');
        };
        $br->exclusive_work($ok2_work);
    };

    subtest work_and_unlock => sub {
        plan tests => 5;
        my $br = $BVSLB->new(-locks => [ @L[0,2] ]);
        is(try_err { $br->exclusive_work($pass_work, 1) },
           undef, 'run and unlock');
        is($L->is_held_sync, 0, 'did unlock');
        is($L[2]->active, 'free', 'also unlocked L2');
        is($L[2]->intent, 'added in ok_work', 'the right L2');
    };

    return;
}


sub contains_tt {
    my ($ds) = @_;

    my %slice = # key => [ want_contains, start, end, (seq_region_id incr)
      (in    => [ 1, 11_000, 19_000 ],
       same  => [ 1, 10_000, 20_000 ],
       diff  => [ 0,  1_000, 90_000, 1 ],
       pokel => [ 0,  9_999, 15_000 ],
       poker => [ 0, 15_000, 20_001 ],
       edgel => [ 0,  9_000, 10_000 ],
       edger => [ 0, 20_000, 25_000 ],
       outer => [ 0,  1_000, 90_000 ],
       left  => [ 0,  5_000,  9_000 ],
       right => [ 0, 21_000, 25_000 ]);

    plan tests => 1 + 4 * keys %slice;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my $S_dba = $ds->get_cached_DBAdaptor->get_SliceAdaptor;

    my $srid = _notlocked_seq_region_id($SLdba);
    my $L = Bio::Vega::SliceLock->new
          (-SEQ_REGION_ID => $srid,
           -SEQ_REGION_START => 10_000,
           -SEQ_REGION_END => 20_000,
           -AUTHOR => _test_author($SLdba, qw( Ubert )),
           -INTENT => 'contains_tt',
           -HOSTNAME => $TESTHOST);

    foreach my $stored (0, 1) {
        foreach my $k (sort keys %slice) {
            my ($want_contains, $start, $end, $srid_add) = @{$slice{$k}};
            my $slice = $S_dba->fetch_by_seq_region_id
              ($srid + ($srid_add || 0), $start, $end);
            is($L->contains_slice($slice), $want_contains && $stored,
               "stored=($stored,1): contains_slice($k)");
            $slice->adaptor(undef);
            is($L->contains_slice($slice), 0,
               "stored=($stored,0): contains_slice($k)");
        }
        $SLdba->store($L) unless $stored;
    }

    my $circ = Bio::EnsEMBL::CircularSlice->new_fast({ circular => 1 }); # junk!
    like(try_err { $L->contains_slice($circ) },
         qr{^ERR:.*CircularSlice is not supported}s,
         'no circular');

    return;
}


# Store(active=pre),unlock - it can be done
sub pre_unlock_tt {
    my ($ds) = @_;
    plan tests => 17;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my ($auth) = _test_author($SLdba, qw( Percy ));
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


# Store,lock,unlock - interaction with another SliceLock,
# (unrealistically but conveniently) from inside the same transaction
sub cycle_tt {
    my ($ds) = @_;
    plan tests => 12;

    # Collect props
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my @author = _test_author($SLdba, qw( Xavier Yuel Zebby ));
    my $BVSL = 'Bio::Vega::SliceLock';
    my @L_pos = (_notlocked_seq_region_id($SLdba),
                 10_000 + int(rand(200_000)), 250_000 + int(rand(150_000)));
    my @R_pos = ($L_pos[0],
                 int( ($L_pos[1] + $L_pos[2]) / 2), # mid
                 $L_pos[2] + 50_000);

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
    is_deeply({ id => $L_slice->get_seq_region_id,
                start => $L_slice->start, end => $L_slice->end },
              { id => $L_pos[0], start => $L_pos[1], end => $L_pos[2] },
              'slice matches L_lock')
      or diag explain { sl => $L_slice, L_lock => $L_lock };
    like($L_lock->describe_slice,
         qr{^[a-z]+:[^:]*:[a-zA-Z]+[^:]*[0-9]+:\d+:\d+:1$},
         'slice description');

    my $R_slice = $SLdba->db->get_SliceAdaptor->fetch_by_seq_region_id(@R_pos);

    # ...lock from slice
    my $R_lock = $BVSL->new
      (-SLICE => $R_slice,
       -AUTHOR => $author[2],
       # -ACTIVE : implicit
       -INTENT => 'testing: boinged off',
       -HOSTNAME => $TESTHOST);

    is_deeply({ id => $R_slice->get_seq_region_id,
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


sub _iso_level {
    my ($dbh, $set_iso) = @_;

    if (defined $set_iso) {
        $set_iso =~ s{-}{ }g;
        $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
        $dbh->commit; # avoid failure inside transaction
        $dbh->do("SET SESSION TRANSACTION ISOLATION LEVEL $set_iso");
        $dbh->begin_work; # make it take effect
    }

    my ($got_iso) = $dbh->selectrow_array('SELECT @@tx_isolation');
    fail("Unexpected isolation '$got_iso'") unless grep { $_ eq $got_iso } @TX_ISO;
    return $got_iso;
}

sub bad_isolation_tt {
    my ($ds, $iso) = @_;
    plan tests => 9;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my $dbh = $SLdba->dbc->db_handle;
    my ($auth) = _test_author($SLdba, qw( Unco ));

    my $lock1 = Bio::Vega::SliceLock->new
      (-SEQ_REGION_ID => 1,
       -SEQ_REGION_START => 1,
       -SEQ_REGION_END   => 10,
       -AUTHOR => $auth,
       -ACTIVE => 'pre',
       -INTENT => "bad_isolation_tt($iso)",
       -HOSTNAME => $TESTHOST);
    $SLdba->store($lock1);

    my $lock2 = Bio::Vega::SliceLock->new
      (-SEQ_REGION_ID => 2,
       -SEQ_REGION_START => 1,
       -SEQ_REGION_END   => 10,
       -AUTHOR => $auth,
       -ACTIVE => 'pre',
       -INTENT => "bad_isolation_tt($iso)",
       -HOSTNAME => $TESTHOST);

    # Enter a mode we don't support
    my $old_iso = _iso_level($dbh);
    isnt($old_iso, $iso, "start: not $iso");
    _iso_level($dbh, $iso); # commit!
    is(_iso_level($dbh), $iso, "middle: $iso !");

    my $lock1_copy = $SLdba->fetch_by_dbID($lock1->dbID);
    is($lock1_copy->author->dbID, $auth->dbID,
       'can fetch'); # no reason yet to prevent it

    my @op = ([ store => $lock2 ],
              [ do_lock => $lock1 ],
              [ unlock => $lock1, $auth ],
              [ bump_activity => $lock1 ],
              [ freshen => $lock1 ]);
    foreach my $op (@op) {
        my ($method, @arg) = @$op;
        like(try_err { $SLdba->$method(@arg) },
             qr{cannot run with .* tx_isolation=READ-},
             "reject insane $method");
    }

    _iso_level($dbh, $old_iso);
    is(_iso_level($dbh), $old_iso, "end: restore $old_iso");
    return;
}


sub _get_DBAdaptor_pair { # + 4 tests, to ensure private-poking worked
    my ($BOLDataset) = @_;

    # Get the cached one as normal
    my $cached = $BOLDataset->get_cached_DBAdaptor;

    # Futz around to defeat every layer of caching
    my $uncached;
    my $key = '_dba_cache';
    my $old = $BOLDataset->{$key};
    {
        local $BOLDataset->{$key} = undef;
        local $cached->dbc->{_host} = 'some.where.else';
        local $SIG{__WARN__} = __muffle
          ('uncache block',
           qr{^WARN: Species .* and group .* same for two seperate databases});
#       local $cached->dnadb->dbc->{_host} = 'different.place.else';
        # dnadb can be shared
        $uncached = $BOLDataset->get_cached_DBAdaptor;
    }

    # Check that we really got a separate connection
    my @dbh = map { $_->dbc->db_handle } ($cached, $uncached);
    my @ptid = map { $_->selectrow_array('SELECT @@pseudo_thread_id') } @dbh;
    is($cached, $old,                'uncached DBAd: $key gives right member');
    cmp_ok($cached, '!=', $uncached, 'uncached DBAd:     DBAdaptors are different');
    cmp_ok($dbh[0], '!=', $dbh[1],   'uncached DBAd:     dbh are different');
    isnt($ptid[0], $ptid[1],         'uncached DBAd:     MySQL-ptid are different');

    # Minor housekeeping upon the connections
    foreach my $dbh (@dbh) {
        _late_commit_register($dbh);
        $dbh->do('SET SESSION lock_wait_timeout = 1');
        $dbh->do('SET SESSION innodb_lock_wait_timeout = 1');
        $dbh->{PrintError} = 0;
    }

    # Mark them, for debug
    $cached->{__get_DBAdaptor_pair} = 'cached';
    $uncached->{__get_DBAdaptor_pair} = 'uncached_alt';

    # Return the pair
    return ($cached, $uncached);
}

sub __muffle {
    my ($during, $ignore_re) = @_;
    return sub { # muffle one specific warning
        my ($msg) = @_;
        warn "[during $during] $msg" unless
          $msg =~ $ignore_re;
    };
}

sub two_conn_tt {
    my ($ds) = @_;
    plan tests => 57;

    my $BVSL = 'Bio::Vega::SliceLock';
    my $WANT_LOCK = [ lock => # from do_lock(,$debug)
                      [ 'race looks won? (rv=1)', # SQL UPDATE rows affected
                        'do_lock=1' ] ]; # do_lock returnvalue
    my $RE_LOCKWAIT = qr{\AERR:.*execute failed: Lock wait timeout exceeded}s;

    my @SLdba = map { $_->get_SliceLockAdaptor } _get_DBAdaptor_pair($ds);
    my @dbh = map { $_->dbc->db_handle } @SLdba;
    my ($auth) = _test_author($SLdba[0], qw( Tango ));
    my %op = _make_test_ops($auth, @SLdba);

    my $tx_iso0 = _iso_level($dbh[0]);

    my $begin = sub {
        foreach my $dbh (@dbh) {
            $dbh->commit unless $dbh->{AutoCommit};
            $dbh->begin_work;
        }
        return;
    };
    my $run_steps = sub {
        my ($label, @step) = @_;
        my @locks;
        $begin->();
        my @result = _action_do_steps([ $label, \@step, \@locks ], \%op);
        my @is_lock = map { defined $_ ? ref($_) : '~' } @locks;
        like("@is_lock", qr{^$BVSL (~|$BVSL)$}, # second may be a failure to fetch a lock (pair0)
           "run_tests($label): (dbh dbh) --> (@is_lock)")
          or diag explain { adap => \@SLdba, locks => \@locks, result => \@result };
        isnt($locks[0]->adaptor, $locks[1] ? $locks[1]->adaptor : undef,
             "$label:   locks not from same adaptor");
        return (@locks, \@result);
    };

    # Show that transactions are isolated.  (We really have @dbh==2)
    {
        my @p0 = $run_steps->(qw( get_pair-commit create        fetch_other no_err ));
        ok($p0[0]->is_stored($SLdba[0]->db), 'pair0.0:   is_stored');
        ok($p0[0]->is_stored($SLdba[1]->db), 'pair0.0:   !is_stored on other db');
        is($p0[1], undef, # dbh[0] did not commit -> not seen at dbh[1]
           'pair0.1:   undef');
    }

    # Show that rows can be seen both sides.  (Normal; like pair0 with commit)
    {
        my @p1 = $run_steps->(qw( get_pair+commit create commit fetch_other no_err ));
        is($p1[0]->seq_region_id, $p1[1]->seq_region_id, 'pair1:   same seq_region_id');
        isnt($p1[0]->adaptor, $p1[1]->adaptor, 'pair1:   different adaptors');

        # $SLdba[1] will not interfere with $SLdba[0]'s object
        foreach my $method (qw( store freshen do_lock bump_activity unlock )) {
            my @arg = ($p1[0]);
            push @arg, $auth if $method eq 'unlock';
            like(try_err { $SLdba[1]->$method(@arg) },
                 qr{^MSG:.*stored with different adaptor}m,
                 "refuse to operate across adaptors: $method");
        }
    }

    # See (eventually) an interruption from the other dbh
    {
        my ($p2_0, $p2_1) = $run_steps->
          (qw( interrupt create lock bump commit ), # dbh[0]
           qw( fetch_other unlock_int no_err )); # dbh[1] - no commit
        is($p2_0->dbID, $p2_1->dbID, 'pair2:   got a pair');
        ok($p2_0->is_held,            'pair2.0:   is_held');
        ok(!$p2_1->is_held,           'pair2.1:   !is_held');
        if ($tx_iso0 eq $ISO_REPEAT) {
            is($p2_0->is_held_sync, 1,
               "pair2.0:   is_held_sync (pre-commit there, $tx_iso0 here)");
            $dbh[1]->commit;
            is($p2_0->is_held_sync, 1,
               "pair2.0:   is_held_sync (committed there, $tx_iso0 here)");
            $dbh[0]->commit;
        } else {
            # The freshen will SELECT...LOCK IN SHARE MODE
            like(try_err { $p2_0->is_held_sync }, $RE_LOCKWAIT,
                 "pair2.0:   is_held_sync: lock timeout ($ISO_SERI)");
            $dbh[0]->commit; # back to AutoCommit, else we cannot SELECT it
            is($p2_0->is_held_sync, 1,
               'pair2.0:   is_held_sync (pre-commit there, AutoCommit here)');
            $dbh[1]->commit;
        }
        # transactions finished both sides, now we will see it
        is($p2_0->is_held_sync, 0,    'pair2.0:   !is_held_sync (committed both)');
        is($p2_0->freed, 'interrupted', 'pair2.0:   freed=interrupted');
    }

    # Interrupted-from-elsewhere prevents explicit unlock
    {
        my ($p3_0, $p3_1, $res) = $run_steps->
          (qw( int_unlock create lock bump commit ), # dbh[0]
           qw(  fetch_other unlock_int commit no_err )); # dbh[1]
        ok($p3_0->is_held, 'pair3.0:   is_held (stale)');
        like(try_err { $p3_0->adaptor->unlock($p3_0, $auth) },
             qr{SliceLock .* was already free .*SET active=free.* failed},
             'pair3.0:   unlock fail (already free)');
        ok(!$p3_0->is_held, 'pair3.0:   !is_held (was freshened)');
        is_deeply($res,
                  [ [create => $p3_0], $WANT_LOCK, [bump => 1], [commit => 1],
                    [fetch_other => $p3_1], [unlock_int => 1], [commit => 1] ],
                  'pair3:   results list')
          or diag explain { adap => \@SLdba, res => $res };
    }

    # In-transaction bump_activity prevents interrupt
    {
        my ($p4_0, $p4_1, $res) = $run_steps->
          (qw( bump_holds create lock commit bump ),
           qw(  fetch_other unlock_int commit ));
        $begin->();
        is($p4_0->is_held_sync, 1, 'pair4.0:   is_held_sync'); # interrupt failed
        my $err = $res->[5][1]; # << error from that which must not succeed
        like($err, $RE_LOCKWAIT, 'pair4.1:   unlock(interrupt) failed');
        is_deeply($res,
                  [ [create => $p4_0], $WANT_LOCK, [commit => 1], [bump => 1],
                    [fetch_other => $p4_1], [unlock_int => $err], [commit=>1] ],
                  'pair4:   result info')
          or diag explain { adap => \@SLdba, res => $res };
    }

    # Standard workflow, overlapping locks
    # (check create(args) works)
    {
        my ($p5_0, $p5_1, $res) = $run_steps->
          (qw( overlap_fail create commit lock commit ),
           [ create => 1250, 2250, 0, 1 ], # on other dbh, region overlap +250bp
           qw(   commit lock commit no_err ));
        is($p5_0->is_held_sync, 1, 'pair5.0:   held');
        is((join ' ', $p5_1->active, $p5_1->freed), 'free too_late',
           'pair5.1:   freed(too_late)');
        my $R_dolock = $res->[6];
        my $L_slid = $p5_0->dbID;
        is_deeply($R_dolock,
                  [ lock => [ "early do_lock / before insert, by slid=$L_slid",
                              '(tidy rv=1)', # the UPDATE did set R_lock free
                              'do_lock=0' ] ], # do_lock returned a fail
                  'pair5:   second lock freed')
          or diag explain $R_dolock;
        is_deeply([ $p5_0->adaptor, $p5_1->adaptor ], \@SLdba,
                  'pair5:   uses alt adaptor');
    }

    # Can insert two SliceLocks on one seq_region without COMMIT,
    # unless one of them is do_lock'd to active=held, because the
    # UPDATE takes a Next-Key Lock.
    #
    # We are safe even if people forget to commit their pre-locks.
    # http://dev.mysql.com/doc/refman/5.5/en/innodb-locks-set.html
    {
        my @p6 = $run_steps->
          (qw( dbl_ins create ), [ create => 1250, 2250, 0, 1 ], qw( no_err ));
        # gets two locks; run_steps checks them

        my @p7_lock0 = $run_steps->
          (qw( ins_lock_ins create lock ),
           [ create => 1250, 2250, 0, 1 ], # timeout
           # next is: push @$lock_stack, (finds nothing);
           qw( fetch_other )); # keep run_steps' @is_lock happy

        my @p8_lock1 = $run_steps->
          (qw( ins_ins_lock create ),
           [ create => 1250, 2250, 0, 1 ],
           qw( lock )); # timeout

        my $err7 = $p7_lock0[-1][2][1];
        my $err8 = $p8_lock1[-1][2][1];
        ( like($err7, $RE_LOCKWAIT, 'pair7:   second INSERT - lock time out') &&
          like($err8, $RE_LOCKWAIT, 'pair8:   UPDATE second - lock time out')
          #  && 0 # wow it really does!
        ) or diag explain({ adap => \@SLdba, no_lock => \@p6,
                            with_lock0 => \@p7_lock0,
                            with_lock1 => \@p8_lock1 });
    }

    # The Next-Key Lock prevents INSERT to regions nearby until
    # commit.
    #
    # This definition of nearby includes seq_region_id in the adjacent
    # gaps, which is more than we need, but not a problem for code
    # that follows the workflow.
    #
    # Just check this doesn't change.
    {
        my $which_srid = 0; # 0 : same as $p9_0,  undef : next or random
        my @out = $run_steps->
          (qw( seq_region_indep create lock ), # dbh[0]
           [ create  => 3000, 4000, $which_srid, 1 ], # dbh[1], fails
           # then because last create made no lock,
           qw( commit fetch_other )); # to please run_steps
        my $res = pop @out;
        my ($p9_0, $p9_1) = @out;
        is($p9_1->is_held_sync, 1, 'pair9.1:   held'); # p9_1 should be fetch_other
        my $err2 = $res->[2][1];
        like($err2, $RE_LOCKWAIT, 'pair9:   second unrelated create blocked');
        is_deeply($res,
                  [ [create => $p9_0], $WANT_LOCK, [create => $err2],
                    [commit=>1], [fetch_other=>$p9_1] ],
                  'pair9:   result info')
          or diag explain { adap => \@SLdba, res => $res };
    }

    $begin->();
    $dbh[1]->disconnect;
    return;
}


# XXX: These look like method calls on something that should be an object
sub _make_test_ops {
    my ($auth, $SLdba,
        $alt_SLdba) # needed only for fetch_other
      = @_;

    return
      (create => sub {
           my ($label, $lock_stack,
               $start, $end, $old_lock_idx, $dbh_n) = @_;
           $start ||= 1000;
           $end   ||= 2000;
           my ($adap, $srid);
           if (defined $old_lock_idx) {
               $adap = $lock_stack->[$old_lock_idx]->adaptor;
               $srid = $lock_stack->[$old_lock_idx]->seq_region_id;
           } else {
               $srid = _notlocked_seq_region_id($SLdba);
           }
           $adap = ($SLdba, $alt_SLdba)[ $dbh_n || 0]
             if !defined $adap || defined $dbh_n;

           my $objnum = @$lock_stack;
           my $lock = Bio::Vega::SliceLock->new
             (-SEQ_REGION_ID => $srid,
              -SEQ_REGION_START => $start,
              -SEQ_REGION_END   => $end,
              -AUTHOR => $auth,
              -INTENT => "timestamps_tt($label) $objnum",
              -HOSTNAME => $TESTHOST);
           $lock->{__origin} = 'create'; # mark it, for debug
           return try_err {
               $adap->store($lock);
               push @$lock_stack, $lock;
               $lock;
           };
       }, drop => sub {
           my ($label, $lock_stack) = @_;
           my $lock = pop @$lock_stack;
           $lock->{__dropped} = 1;
           return $lock;
       }, fetch_other => sub {
           my ($label, $lock_stack) = @_;
           my $dbid = $lock_stack->[-1]->dbID;
           my $lock = $alt_SLdba->fetch_by_dbID($dbid);
           $lock->{__origin} = 'fetch_other' if $lock; # mark it, for debug
           push @$lock_stack, $lock;
           $lock;
       }, commit => sub {
           my ($label, $lock_stack) = @_;
           my $lock = $lock_stack->[-1];
           my $dbh = $lock->adaptor->dbc->db_handle;
           $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
           $dbh->commit;
           $dbh->begin_work;
           return 1;
       }, lock => sub {
           my ($label, $lock_stack) = @_;
           my $lock = $lock_stack->[-1];
           return try_err {
               my $debug = []; # for the "confused, active=pre" message (if any)
               my $rv = $lock->adaptor->do_lock($lock, $debug);
               push @$debug, "do_lock=$rv";
               $debug;
           };
       }, bump => sub {
           my ($label, $lock_stack) = @_;
           my $lock = $lock_stack->[-1];
           return try_err { $lock->bump_activity };
       }, unlock => sub {
           my ($label, $lock_stack) = @_;
           my $lock = $lock_stack->[-1];
           return try_err { $lock->adaptor->unlock($lock, $auth) };
       }, unlock_int => sub {
           my ($label, $lock_stack) = @_;
           my $lock = $lock_stack->[-1];
           my ($auth_i) = _test_author($lock->adaptor, qw( Ian ));
           return try_err { $lock->adaptor->unlock($lock, $auth_i, 'interrupted') };
       });
}

sub _action_do_steps {
    my ($case, $ops, $on_error) = @_;
    my ($label, $steps, $lock_stack) = @$case;
    my @done;
    $on_error = pop @$steps if $steps->[-1] eq 'no_err';
    while (@$steps) {
        my $step = shift @$steps;
        last if $step eq 'wait'; # next time
        my @arg;
        ($step, @arg) = @$step if ref($step) eq 'ARRAY';
        my $code = $ops->{$step}
          or die "Bad step name '$step' in label=$label";
        my $ret = $code->($label, $lock_stack, @arg);
        push @done, [ $step, $ret ];
        die "failed:$label (op: $step, remaining: @$steps) -> $ret"
          if $on_error && defined $ret && $ret =~ m{^ERR:};
    }
    return @done;
}

sub timestamps_tt {
    my ($ds) = @_;
    plan tests => 9;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my ($auth) = _test_author($SLdba, qw( Terry ));
    my %op = _make_test_ops($auth, $SLdba);

    # Interlocking cases run to minimise test-time wallclock duration
    my @actions =
      (# label => [ ...steps... ], \@lock_stack, { field => expect }
       [ A => [qw[ create wait create ]], [],
         { ts_begin => 'incr' }
         # i.e. Timestamp increased when second active=pre is made
       ],
       [ B => [qw[ create wait lock ]], [],
         { ts_begin => 'same', ts_activity => 'incr' },
         # In do_lock, retain the ts_begin but bump ts_activity.
         # Generally "pre" phase is short.
       ],
       [ C => [qw[ create lock wait bump ]], [],
         { ts_begin => 'same', ts_activity => 'incr' },
         # The bump operation, recommended for use with COMMIT, moves
         # ts_begin only.
       ],
       [ D => [qw[ create lock wait unlock ]], [],
         { ts_begin => 'same',
           ts_free => 'huge', # "before" was undef so delta is huge
           ts_activity => 'same' }
       ]);

    my %product; # key = label, value = [ $before_times, $after_times ]
    # %$each_times are key = fieldname, value = timestamp; taken before+after "wait"

    # Do the actions, consuming all steps in the process
    foreach my $when (0, 1) { # 0 = before, 1 = after
        foreach my $case (@actions) {
            _action_do_steps($case, \%op, 1);
            my ($label, $steps_left, $lock_stack, $fieldset) = @$case;
            fail("More 'wait' than \$when in label=$label") if @$steps_left && $when;
            foreach my $field (keys %$fieldset) {
                my $lock = $lock_stack->[-1];
                $product{$label}->[$when]->{$field} = $lock->$field;
            }
        }
        sleep 1 unless $when;
    }

    my %ts_diff; # key = label, value = { $fieldname => $seconds_delta }
    foreach my $case (@actions) {
        my ($label, $steps, $lock_stack, $fieldset) = @$case;
        my $info = $product{$label};
        foreach my $fieldname (keys %$fieldset) {
            my $got_num = $ts_diff{$label}->{$fieldname} =
              $info->[1]->{$fieldname} - ($info->[0]->{$fieldname} || 0);

            my $want = $fieldset->{$fieldname};
            my $got_txt;
            if    ($got_num  < 0) { $got_txt = 'decr' } # weird
            elsif ($got_num == 0) { $got_txt = 'same' }
            elsif ($got_num < 60) { $got_txt = 'incr' }
            elsif ($got_num > 1300_000_000) { $got_txt = 'huge' } # unixtime
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


sub fetchby_tt {
    my ($ds) = @_;
    plan tests => 7;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    # db should contain a motley assortment of locks under $TESTHOST
    # but the exact collection will be a little unstable as tests change

    my (%act, %n);
    my $get_act = sub {
        %act = (def  => $SLdba->fetch_by_active(),
                held => $SLdba->fetch_by_active('held'),
                pre  => $SLdba->fetch_by_active('pre'),
                free => $SLdba->fetch_by_active('free'));
        foreach my $list (values %act) {
            @$list = grep { $_->hostname eq $TESTHOST } @$list;
        }
        @n{keys %act} = map { scalar @$_ } values %act;
        return;
    };
    $get_act->();

    # Need some locks left over from previous tests, else we are sunk
    foreach my $key (qw( pre held free )) {
        cmp_ok($n{$key}, '>=', 2, "fetch_by_active: have some $key");
    }

    is($n{def}, $n{held}, 'fetch_by_active: default=held');

    my @to_free = ($act{held}[0], $act{held}[1], $act{pre}[0]);
    foreach my $L (@to_free) {
        $SLdba->unlock($L, $L->author);
    }

    my %old_n = %n;
    $get_act->();
    is($n{held} + 2, $old_n{held}, 'freed: two held');
    is($n{pre}  + 1, $old_n{pre}, 'freed: one pre');
    is($n{free} - 3, $old_n{free}, 'freed: three more');

    return;
}


sub json_tt {
    my ($ds) = @_;
    plan tests => 10;

    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my ($auth) = _test_author($SLdba, qw( Jason ));
    my $Lreal = Bio::Vega::SliceLock->new
      (-SLICE => _arbitrary_slice($ds),
       -AUTHOR => $auth,
       -INTENT => 'cereal',
       -HOSTNAME => $TESTHOST);

    like(try_err { $Lreal->TO_JSON }, qr{unstored .* not supported}, 'unstored');
    $SLdba->store($Lreal);
    my $t0  = $Lreal->ts_activity;
    my $t0i = $Lreal->iso8601_ts_activity;

    my %Jreal_exp =
      (dbID => $Lreal->dbID,
       seq_region_id    => $Lreal->seq_region_id,
       seq_region_start => $Lreal->seq_region_start,
       seq_region_end   => $Lreal->seq_region_end,
       slice_name       => $Lreal->slice->name,
       ts_begin    => $t0,
       ts_activity => $t0,
       ts_free     => undef,
       active        => 'pre',
       freed         => undef,
       intent        => 'cereal',
       hostname      => $TESTHOST,
       otter_version => undef,
       author_id       => $auth->dbID,
       freed_author_id => undef,
       # FYI fields
       iso8601_ts_begin    => $t0i,
       iso8601_ts_activity => $t0i,
       iso8601_ts_free     => 'Tundef',
       author_email        => $auth->email,
       freed_author_email  => undef,
      );
    is_deeply($Lreal->TO_JSON, \%Jreal_exp, 'Jreal (stored)');

    my $Lview1 = Bio::Vega::SliceLock->new_from_json(%Jreal_exp);
    my $Lview2 = Bio::Vega::SliceLock->new_from_json($Lreal->TO_JSON);
    is_deeply($Lview1, $Lview2, 'lock, restored 1st==2nd');

    is_deeply($Lview1->TO_JSON, $Lreal->TO_JSON, 'restored == serialised');

    like(try_err { $Lview1->adaptor($SLdba) }, qr{^ERR:.*adaptor is immutable}s,
         "dbop: adaptor");
    like(try_err { $Lview1->is_held_sync },
         qr{^ERR:.*unblessed reference}, "dbop: is_held_sync");
    like(try_err { $SLdba->bump_activity($Lview1) },
         qr{^ERR:.*stored with different adaptor ARRAY}s, "dbop: bump");
    like(try_err { $SLdba->freshen($Lview1) },
         qr{^ERR:.*stored with different adaptor ARRAY}s, "dbop: freshen");

    $Jreal_exp{freed} = { here => 'yes', there => 'no' };
    like(try_err { Bio::Vega::SliceLock->new_from_json(%Jreal_exp) },
         qr{Non-scalar}, "bad non-flat input");
    delete $Jreal_exp{freed};
    $Jreal_exp{spork} = "munch";
    like(try_err { Bio::Vega::SliceLock->new_from_json(%Jreal_exp) },
         qr{Unrecognised}, "bad non-flat input");

    return;
}


sub broker_tt {
    plan tests => 7;
    my ($species, $species_alt) = qw( human_dev human_test );
    my ($ds, $ds_alt) = get_BOLDatasets($species, $species_alt);
    my ($dbname, $dbname_alt) = qw( jgrg_human_dev jgrg_human_test );

    my $BVSLB = 'Bio::Vega::SliceLockBroker';
    my $BV_SLA = 'Bio::Vega::DBSQL::SliceLockAdaptor';
    my $SLdba = $ds->get_cached_DBAdaptor->get_SliceLockAdaptor;
    my @author = _test_author($SLdba, qw( Sledge Jemmy Reckon ));

    my $dba_alt = $ds_alt->get_cached_DBAdaptor;
    isnt($ds->name, $ds_alt->name, 'have two datasets');

    like(Bio::Vega::SliceLockBroker::__dbc_str($SLdba->dbc), ## no critic (Subroutines::ProtectPrivateSubs)
         qr{-PASS='redact'}, 'password redaction');

    subtest adaptor_types => sub {
        plan tests => 8;
        like(try_err { $BVSLB->new(-adaptor => 'Bob') },
             qr{^ERR:.*MSG: Cannot get_SliceLockAdaptor from Bob: Can't locate object method}s, 'txt');

        my $edba = $ds->make_EnsEMBL_DBAdaptor;
        isa_ok($edba,    'Bio::EnsEMBL::DBSQL::DBAdaptor', 'edba type');
        isa_ok($dba_alt, 'Bio::Vega::DBSQL::DBAdaptor', 'dba_alt type');
        isa_ok($BVSLB->new(-adaptor => $dba_alt)->adaptor,
               $BV_SLA, 'dba_alt to SLdba');
        is($BVSLB->new(-adaptor => $SLdba)->adaptor, $SLdba, 'SLdba passthrough');
        isa_ok($BVSLB->new(-adaptor => $dba_alt->get_SliceAdaptor)->adaptor,
               $BV_SLA, 'SliceAdaptor to SLdba');

        my $fail_re = # has %s values: type species group
          qr{Could not (get adaptor SliceLock|find SliceLock adaptor in the registry) for $species otter:Bio::EnsEMBL::DBSQL::DBAdaptor};
        local $SIG{__WARN__} = __muffle(__dba_to_sldba => $fail_re);
        like(try_err { $BVSLB->new(-adaptor => $edba) },
             qr{^ERR:.*MSG: $fail_re}s, 'edba does not know how');
        like(try_err { $BVSLB->new(-adaptor => $edba->get_SliceAdaptor) },
             qr{^ERR:.*MSG: $fail_re}s, 'edba SliceAdaptor does not know how');
    };

    subtest props => sub {
        plan tests => 24;
        my $br = $BVSLB->new;
        foreach my $method (qw( hostname author adaptor )) {
            like(try_err { $br->$method },
                 qr{^ERR:.*MSG: $method not yet available}s, "empty->$method");
        }
        is_deeply([ $br->locks ], [], "empty->locks");

        is($br->have_db, 0, '!have_db');
        like(try_err { $br->author($author[0]) },
             qr{^ERR:.*MSG: author must be stored.*adaptor is not yet set}s,
             'unsaved author before adaptor');
        is($author[0]->dbID,    undef, 'author[0] is unsaved [dbID]');
        is($author[0]->adaptor, undef, 'author[0] is unsaved [adaptor]');

        # Set, with no locks
        $br->hostname($TESTHOST);
        $br->adaptor($SLdba);
        $br->author($author[0]);
        is($br->hostname, $TESTHOST,  'hostname set');
        is($br->adaptor,  $SLdba,     'adaptor set');
        is($br->author,   $author[0], 'author set');

        is($br->have_db, 1, 'have_db');
        isnt($author[0]->dbID,    undef, 'author[0] was saved [dbID]');
        isnt($author[0]->adaptor, undef, 'author[0] was saved [adaptor]');
        is($author[1]->adaptor, undef, 'author[1] is unsaved [adaptor]');
        $dba_alt->get_AuthorAdaptor->store($author[2]);

        # Try to change
        my @change =
          ([ hostname => 'elsewhere.local',
             qr{.*have test\.nowhere, tried to set elsewhere\.local} ],
           [ adaptor => $dba_alt->get_SliceLockAdaptor,
             qr{dbc mismatch: have \S+::SliceLockAdaptor=\S+ \(-DBNAME='$dbname'[^)]+\), tried to set \S+::SliceLockAdaptor=\S+ \(-DBNAME='$dbname_alt'[^)]+\)} ],
           [ author => $author[1],
             qr{author mismatch: have #\d+, tried to set #\d+} ],
           [ author => $author[2],
             qr{dbc mismatch: have .*'$dbname'.*tried to set.*'$dbname_alt'} ],
           [ hostname => undef, qr{Cannot unset hostname} ],
           [ author => undef,   qr{Cannot unset author} ],
           [ adaptor => undef,    qr{Cannot unset adaptor} ]);
        foreach my $pair (@change) {
            my ($method, $val, $err_re) = @$pair;
            like(try_err { $br->$method($val) },
                 qr{^ERR:.*MSG: $err_re}s,
                 "filled->$method(diff)");
        }

        # author got saved but we didn't use it.  Then in real code
        # presumably a ROLLBACK, and one autoincr value is wasted.
        isnt($author[1]->adaptor, undef, 'author[1] was saved [adaptor]');

        like(try_err { $BVSLB->new(-author => $author[1], -adaptor => $dba_alt) },
             qr{dbc mismatch: have .*'$dbname_alt'.*tried to set.*'$dbname'},
             'new can fail, dba is set before author');
    };

    subtest props_from_lock => sub {
        plan tests => 2;
        my $br = $BVSLB->new;
        my ($auth) = _test_author($SLdba, qw( Luke ));
        my $l = Bio::Vega::SliceLock->new
          (-SEQ_REGION_ID => _notlocked_seq_region_id($SLdba),
           -SEQ_REGION_START => 500, -SEQ_REGION_END => 1000,
           -INTENT => 'props_from_lock',
           -HOSTNAME => $TESTHOST, -AUTHOR => $auth);
        like(try_err { $br->locks($l) },
             qr{MSG: adaptor not yet available}, 'no database linkage');
        $SLdba->db->get_AuthorAdaptor->store($auth);
        # $SLdba->store($l);
        #    we already know this store would first store $auth,
        #    so we learn nothing by also testing that case
        $br->locks($l);
        is(scalar $br->locks, 1, 'stored and listed');
    };

    subtest locks_create => sub {
        plan tests => 15;
        my $br = $BVSLB->new(-hostname => $TESTHOST, -author => $author[1]);
        is(scalar $br->locks, 0, 'made with no locks');
        my $srid = _notlocked_seq_region_id($SLdba);
        my $l = $br->lock_create_for_Slice # it has $SLdba via -author
          (-seq_region_id => $srid,
           -seq_region_start => 1000,
           -seq_region_end => 9000);
        is(try_err { $l->active }, 'pre', 'create leaves active=pre');
        ok($l->is_stored($SLdba->dbc), 'create did store');
        is(scalar $br->locks, 1, 'lock is added');
        is($l->intent, 'via SliceLock.t', 'inferred intent');
        is($l->hostname, $TESTHOST, 'copied hostname');
        is($l->otter_version, Bio::Otter::Version->version, 'implicit otter_version');

        my $dbh = $l->adaptor->dbc->db_handle;
        $dbh->begin_work if $dbh->{AutoCommit}; # avoid warning
        $dbh->commit;
        $dbh->begin_work;

        my $l2 = $br->lock_create_for_Slice
          (-seq_region_id => $srid,
           -seq_region_start => 20000,
           -seq_region_end => 25000);
        is_deeply([ sort __by_dbID $br->locks ], # order is not guaranteed
                  [ sort __by_dbID ($l, $l2) ],
                  'multiple locks in collection');
        $dbh->rollback;

        is($l->is_held_sync, 0, 'l still exists(pre) [commit]');
        like(try_err { $l2->is_held_sync }, qr{Freshen.* failed, row not found},
             'l2 is gone [rollback]');

        my $br2 = $BVSLB->new(-locks => [ $l2, $l ]); # re-use invalid lock!
        is_deeply([ sort __by_dbID $br2->locks ], # order is not guaranteed
                  [ sort __by_dbID ($l, $l2) ],
                  'reconstruct with multiple locks');

        my @argset =
          ([ -locks  => [ $l ]       ],
           [ -locks  =>   $l         ],
           [ -lockid => [ $l->dbID ], -adaptor => $SLdba ],
           [ -lockid =>   $l->dbID  , -adaptor => $SLdba ]);
        for (my $i=0; $i<@argset; $i++) {
            my @arg = @{ $argset[$i] };
            is_deeply([ $BVSLB->new(@arg)->locks ], [ $l ],
                      "reconstruct with one lock i=$i");
        }
    };

    subtest author_for_uid => sub {
        plan tests => 2;
        my @a_arg = (-author => 'for_uid');
        like(try_err { $BVSLB->new(@a_arg) },
             qr{^MSG: author must be stored .* broker adaptor is not yet set$}m,
             'needs adaptor');
        like(try_err { $BVSLB->new(-adaptor => $SLdba, @a_arg)->author->email },
             qr{^\w+$}, # a "staff" email, as Bio::Vega::Author->new_for_uid
             "convenient @a_arg");
    };

    return;
}

sub __by_dbID {
    return $a->dbID <=> $b->dbID;
}


sub _support_which {
    my ($thing) = @_;
    my @out;
    push @out, try {
        Bio::Vega::SliceLockBroker->supported($thing) ? ('new') : (),
      } catch {
          ("new:ERR:$_");
      };
    return \@out;
}


exit main();
