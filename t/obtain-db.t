#! /usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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
use Test::Otter qw( ^db_or_skipall OtterClient try_err );

use YAML 'Dump'; # for diag
use File::Slurp 'read_dir';
use Try::Tiny;

use Net::Netrc;
use DBI;
use Bio::Otter::SpeciesDat;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Server::Config;

use Test::Requires qw(Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor);

=head1 NAME

obtain-db.t - see that we can talk to database servers

=head1 DESCRIPTION

This test connects to database servers.  It makes no lasting changes,
but in some cases it must satisfy itself that it has a read-only or
read-write connection.

=head2 Aims

=over 4

=item *

Exercise all the supported methods of connecting.  Complete?

=item *

Ensure all routes lead to the same place.  Incomplete.

=item *

Ensure L<Bio::Otter::SpeciesDat::DataSet/clone_readonly> gives the
right database, and it is actually read-only.

=item *

Ensure all configured databases are available.
Incomplete, but see webvm.git F<cgi-bin/selftest/05database-access.t>

=item *

Ensure DNA sequence can be fetched, to exercise the cases using
C<DNA_DBNAME>.

=item *

For read-write databases, check the transaction isolation mode.
The SliceLock tests do this, for selected datasets.

=item *

Check locales, collation orders, timezones, idle-disconnect settings,
error raising...  later!

=item *

Check Ensembl schema version numbers.  Later.

=back

Some of these aims may be better split out to a combination of
database enumeration module & another test script.


=head1 CONNECTION ROUTES

There are several ways to obtain database connection parameters, some
of which would work outside the firewall.  However there is no support
for connecting from outside so we skip the tests in this case.

There are also at least two classes of code making these connections:
ensembl-otter and ensembl-pipeline.

=head2 By commandline argument

Some scripts take L<DBI>-like connection parameters: host, port, user,
dbname.

Some also take an explicit password.  This script needs a password
file on disk and ignores the "explicit password" variation.

=head2 Direct access to Otter Data directory

Use the Otter Server's data files to reach databases.

=head2 Via Otter Server

Call the Otter Server as a client and ask for datasets.


=head1 SEE ALSO

F<scripts/lace/example_script>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut


sub main {
    plan tests => 8;

    my @warn;
    local $SIG{__WARN__} = sub {
        push @warn, "@_";
#        warn "@_";
    };

    subtest "cmdline, loutre" => sub {
        cmdline_tt({qw{ host otterlive database loutre_human }},
                   [ 'loutre_human by netrc args', 'human', 'ensembl:loutre' ]);
    };

    subtest "cmdline, pipe" => sub {
        cmdline_tt({qw{ host otp1-db database pipe_human }},
                   [ 'pipe_human by netrc args', 'human', 'ensembl:pipe' ]);
    };

    subtest "server, human" => sub {
        server_tt('human',
                  [ 'loutre_human as server', 'human', 'ensembl:loutre' ],
                  [ 'pipe_human as server', 'human', 'ensembl:pipe' ]);
    };

    subtest "client, human" => sub {
        client_tt('human',
                  [ 'loutre_human via Server', 'human', 'ensembl:loutre' ],
                  [ 'pipe_human via Server', 'human', 'ensembl:pipe' ]);
    };

    subtest "client, human_dev" => sub {
        client_tt('human_dev',
                  [ 'loutre_(human_dev) via Server', 'human', 'ensembl:loutre' ],
                  [ 'pipe_(human_dev) via Server', 'human', 'ensembl:pipe' ]);
    };

    subtest "BOSDataSet readonly" => __PACKAGE__->can('readonly_ds_tt');

  TODO: {
        local $TODO = "Not tested";
        fail('Test *_variation DBAdaptors');
    }

  TODO: {
        local $TODO = "Noise to a logger";
        is(scalar @warn, 0, "warnings") || diag(Dump({ warnings => \@warn }));
    }

    return ();
}


sub cmdline_tt {
    my ($args, $check) = @_;
    plan tests => 3;

    my $dbh = try { netrc_dbh(%$args) } catch { "perl_err=$_" };
    check_dbh($dbh, @$check);

    return ();
}


sub server_tt {
    my ($dataset_name, $check_loutre, $check_pipe) = @_;
    plan tests => 4;

    my $dataset = SpeciesDat()->dataset($dataset_name);
    check_dba($dataset->otter_dba, @$check_loutre);
    check_dba($dataset->pipeline_dba('pipe', 'rw'), @$check_pipe);

    # The server doesn't have ensembl-pipeline so its scripts want a
    # vanilla DBA
    is(ref($dataset->pipeline_dba), 'Bio::Vega::DBSQL::DBAdaptor',
       "$dataset_name pipe: server needs vanilla");

    # Despite fixing a caching bug in BOS:DataSet, this is broken.
    # For now we only ensure it isn't silently broken.
    my $dba_rw = try { ref($dataset->pipeline_dba('rw')) } catch { "ERR:$_" };
    like($dba_rw, qr/^Bio::EnsEMBL::DBSQL::DBAdaptor$|^ERR:/,
         "$dataset_name pipe: caching bug must not be silent");

    return ();
}


sub client_tt {
    my ($dataset_name, $check_loutre, $check_pipe) = @_;
    plan tests => 3;

    my $cl = OtterClient();
    my $dataset = $cl->get_DataSet_by_name($dataset_name);

## XXX: asymmetry between BOL:SpeciesDat::DataSet and BOL:DataSet
#    check_dbh($dataset->otter_dba->dbc->db_handle, @$check_loutre);
#    check_dbh($dataset->pipeline_dba->dbc->db_handle, @$check_pipe);

    my $o_dba = $dataset->get_cached_DBAdaptor;
    my $p_dba = $dataset->get_pipeline_DBAdaptor('rw');
    my $p_dba_ro = $dataset->get_pipeline_DBAdaptor;
    check_dba($o_dba, @$check_loutre);

    my $pipe_what = shift @$check_pipe;
    check_dba($p_dba, $pipe_what, @$check_pipe);
    check_dba($p_dba_ro, "$pipe_what (ro)", @$check_pipe);

    return ();
}

sub readonly_ds_tt {
    my @all_ds = SpeciesDat()->all_datasets;
    plan tests => 10 * @all_ds;
    foreach my $ds (@all_ds) {
        my $name = $ds->name;
        my $ds_ro = $ds->clone_readonly;
        my $ok = 1;
        # Is it the same thing?
        is_deeply(_db_fingerprint($ds_ro),
                  _db_fingerprint($ds),
                  "fingerprint of BOSD($name)->clone_readonly")
          or $ok=0;
        # Is it read-only? (both parts)
        be_readonly("$name(r-o)", $ds_ro->otter_dba->dbc->db_handle)
          or $ok=0;
      SKIP: {
            my $name_dna = $ds_ro->DNA_DBNAME;
            skip("ds=$name has no DNA_DBNAME" => 3) unless $name_dna;
            be_readonly("$name(r-o)~DNA", $ds_ro->otter_dba->dnadb->dbc->db_handle)
              or $ok=0;
        }
        is($ds_ro->clone_readonly, $ds_ro, 'readonly of readonly is self')
          or $ok=0;
# die explain({ ds_params => $ds->ds_all_params, ro_params => $ds_ro->ds_all_params }) unless $ok;
    }
    return;
}

sub _db_fingerprint {
    my ($ds) = @_;
    my $dbh = $ds->otter_dba->dbc->db_handle;
    my $ds_name = $ds->name;
    $ds_name .= '(r-o)' if $ds->READONLY;
    return try {
        my %out;
        $out{meta} = $dbh->selectall_arrayref('select * from meta');
        $out{schemas} = $dbh->selectall_arrayref('show databases');
        my ($slinfo, $slice) = _dba2subslice($ds_name, $ds->otter_dba);
        $out{$slinfo} = $slice->seq;
        \%out;
    } catch {
        "ERR:$ds_name: $_"; # $ds_name should ensure a difference in output
    };
}

# plan += 3
sub be_readonly { # XXX:DUP team_tools.git cron/t/otter_databases.t
    my ($what, $dbh) = @_;
    my $ok = 1;

    my $ins = try_err {
        local $SIG{__WARN__} = sub { };
        $dbh->begin_work if $dbh->{AutoCommit};;
        $dbh->do("insert into meta (species_id, meta_key, meta_value) values (null, ?,?)", {},
                 "be_readonly.$0", scalar localtime);
        "Inserted";
    };
    like($ins,
         qr{INSERT command denied to user|MySQL server is running with the --read-only option},
         "$what: Insert to meta") or $ok=0;
    $dbh->do("rollback");

    my $read = $dbh->selectall_arrayref("SELECT * from meta");
    ok(scalar @$read, "$what: meta not empty") or $ok=0;

    my @was_not_readonly = grep { row_as_text($_) =~ /:be_readonly/ } @$read;
    ok(!@was_not_readonly, "$what: test row is absent") or $ok=0;
    diag Dump(\@was_not_readonly) if @was_not_readonly;
    die "abort - I am leaving droppings?" if @was_not_readonly;

    return $ok;
}
sub row_as_text {
    my ($row) = @_;
    return join ":", map { defined $_ ? $_ : "(undef)" } @$row;
}


sub check_dba {
    my @arg = my ($dba, $what, $species_want, $schema_want) = @_;
    return subtest "check_dba($what)" => sub { _check_dba(@arg) };
}
sub _check_dba {
    my ($dba, $what, $species_want, $schema_want) = @_;
    plan tests => 6;

    my $dbh = $dba->dbc->db_handle;
    my $schema_got = guess_schema($dbh);

    # check type
    my $class_want =
      { 'ensembl:loutre' => 'Bio::Vega::DBSQL::DBAdaptor',
        'ensembl:pipe' => 'Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor',
      }->{$schema_want} || 'some subclass of DBAdaptor';

  SKIP: {
        skip("not an expected ensembl class" => 2) unless
          is(ref($dba), $class_want, "$what: class");

        # check we can get genomic sequence, i.e. DNADB works
        try {
            my ($checkname, $checkslice) = _dba2subslice($what, $dba);
            my $seq = $checkslice->seq;
            $seq =~ s{(N+)}{'('.length($1).' Ns)'}e;
            like($seq, qr{[ACGT]{1000,}}, "$checkname has sequence");
        } catch {
            fail($_);
        };
    }

    check_dbh($dbh, $what, $species_want, $schema_want);
    return ();
}


# $dbh: can proceed with a DBI handle or a problem string
sub check_dbh {
    my ($dbh, $what, $species_want, $schema_want) = @_;

  SKIP: {
        my $ping;
        $ping = "not a dbh: $dbh" unless ref($dbh);
        $ping ||= $dbh->ping ? 'ping' : 'broken';
        is($ping, 'ping', "$what: ping")
          or skip("no database handle for $what" => 2);

        my $schema_got = guess_schema($dbh);
        is($schema_got, $schema_want, "$what: schema type");

        my $species_got = rowhash($dbh, q{select * from meta where meta_key = 'species.common_name'});
        is($species_got->{'meta_value'}, $species_want, "$what: species")
          || diag(Dump($species_got));
    }

    return ();
}


### Utility functions - could be more useful elsewhere
#

sub netrc_dbh {
    my %args = @_;

    my $ref = Net::Netrc->lookup($args{'host'})
      or die "No entry found in ~/.netrc for host $args{'host'}";
    @args{qw{ user pass port }} = ($ref->login, $ref->password, $ref->account);

    my $dsn = "DBI:mysql:". join ';', map {"$_=$args{$_}"} qw( database host port );
    return DBI->connect($dsn, @args{qw{ user pass }}, { 'RaiseError' => 1 });
}


{
    my $sp_dat;
    sub SpeciesDat {
        $sp_dat ||= Bio::Otter::Server::Config->SpeciesDat;
        return $sp_dat;
    }
}


sub rowhash {
    my ($dbh, $sql) = @_;
    return try {
        local $dbh->{PrintError} = 0;
        $dbh->selectrow_hashref($sql)
          || { DBI_err => $dbh->err };
    } catch {
        { perl_err => $_ }
    };
}

sub fields_string {
    my ($rowhash) = @_;
    return join ':', map { lc($_) } sort keys %$rowhash;
}

sub field_exist {
    my ($want, $rowhash) = @_;
    return grep { lc($_) eq $want } keys %$rowhash;
}

sub guess_schema {
    my ($dbh) = @_;
    my @type;

    my $meta = rowhash($dbh, 'select * from meta');
    my $sr = rowhash($dbh, 'select * from seq_region limit 1');
    push @type, 'ensembl' if field_exist(coord_system_id => $sr)
      && fields_string($meta) eq 'meta_id:meta_key:meta_value:species_id';

    my $ga = rowhash
      ($dbh, 'select * from gene g
 join gene_author ga using (gene_id)
 join author using (author_id)
 limit 1');
    push @type, 'loutre' if field_exist(author_name => $ga);

    my $rcga = rowhash
      ($dbh, 'select a.logic_name,rg.rule_id,rc.rule_condition
 from rule_conditions rc,rule_goal rg, analysis a
 where a.analysis_id = rg.goal and rg.rule_id = rc.rule_id');
    push @type, 'pipe' if field_exist(logic_name => $rcga);

    my $proj_acc = rowhash
      ($dbh, 'select * from sequence
 join project_dump using (seq_id)
 join project_acc using (sanger_id)
 limit 1');
    push @type, 'submissions' if field_exist(htgs_phase => $proj_acc);

    return join ':', sort @type;
}

# Return a well-defined (name, subslice) which isn't too big; or error
#
# plan += 1
sub _dba2subslice {
    my ($what, $dba) = @_;

    # Define "nice".  Rules are fiddled to work with current datasets.
    my $sr_niceness = sub {
        my ($sr) = @_;
        my $lendiff = $sr->length - 1E6;
        return -log(1+abs($lendiff)) # log difference from 1 Mbase,
          +($lendiff > 0 ? 10 : 0) # bonus for being long enough to have data
          -($sr->seq_region_name =~ /^chr\d+-/ ? 0 : 20); # weird name penalty
    };

    # Select a nice chromosome.
    my @chr = @{ $dba->get_SliceAdaptor->fetch_all('chromosome', 'Otter') };
    die "Found no chromosome:Otter in $what" unless @chr;
    my ($any_chr) = sort { $sr_niceness->($b) <=> $sr_niceness->($a) } @chr;
    my $name = $any_chr->display_id;
    my $mid = int($any_chr->centrepoint);
    my $out = $any_chr->sub_Slice($mid - 50_000, $mid + 50_000, 1);

    if (!$out) {
        my %score = map {( $_->display_id, $sr_niceness->($_) )} @chr;
        note explain { chr => \%score };
        die "Can't get sub_Slice at mid=$mid of any_chr=$name from $what";
    }
    isa_ok($out, 'Bio::EnsEMBL::Slice', "$what subslice");
    return ($out->display_id, $out);
}

#
###


main();
