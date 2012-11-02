#! /usr/bin/env perl

use strict;
use warnings;

use Test::More;
use t::lib::Test::Otter qw( ^db_or_skipall );

use YAML 'Dump'; # for diag
use File::Slurp 'read_dir';
use Try::Tiny;

use Net::Netrc;
use DBI;
use Bio::Otter::SpeciesDat;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Server::Config;


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

Ensure all configured databases are available.  Incomplete.

=item *

For read-write databases, check the transaction isolation mode.
Later!

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
    plan tests => 30;

    my @warn;
    local $SIG{__WARN__} = sub {
        push @warn, "@_";
#        warn "@_";
    };

    # 3
    cmdline_tt({qw{ host otterlive database loutre_human }},
               [ 'loutre_human by args', 'human', 'ensembl:loutre' ]);

    # 3
    cmdline_tt({qw{ host otterpipe1 database pipe_human }},
               [ 'pipe_human by args', 'human', 'ensembl:pipe' ]);

    # 10
    server_tt('human',
              [ 'loutre_human as server', 'human', 'ensembl:loutre' ],
              [ 'pipe_human as server', 'human', 'ensembl:pipe' ]);

    # 12
    client_tt('human',
              [ 'loutre_human via Server', 'human', 'ensembl:loutre' ],
              [ 'pipe_human via Server', 'human', 'ensembl:pipe' ]);

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

    my $dbh = try { netrc_dbh(%$args) } catch { "perl_err=$_" };
    check_dbh($dbh, @$check);

    return ();
}


sub server_tt {
    my ($dataset_name, $check_loutre, $check_pipe) = @_;

    my $dataset = SpeciesDat()->dataset($dataset_name);
    check_dba($dataset->otter_dba, @$check_loutre);
    check_dba($dataset->pipeline_dba('pipe', 'rw'), @$check_pipe);

    # The server doesn't have ensembl-pipeline so its scripts want a
    # vanilla DBA
    is(ref($dataset->pipeline_dba), 'Bio::EnsEMBL::DBSQL::DBAdaptor',
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


sub check_dba {
    my ($dba, $what, $species_want, $schema_want) = @_;

    my $dbh = $dba->dbc->db_handle;
    my $schema_got = guess_schema($dbh);

    # check type
    my $class_want =
      { 'ensembl:loutre' => 'Bio::Vega::DBSQL::DBAdaptor',
        'ensembl:pipe' => 'Bio::EnsEMBL::Pipeline::DBSQL::Finished::DBAdaptor',
      }->{$schema_want} || 'some subclass of DBAdaptor';

    is(ref($dba), $class_want, "$what: class");

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
        local $ENV{DOCUMENT_ROOT} = '/nfs/WWWdev/SANGER_docs/htdocs';
        # ugh, but B:O:S:C needs it (at v67..70)

        $sp_dat ||= Bio::Otter::Server::Config->SpeciesDat;
        return $sp_dat;
    }
}

{
    my $cl;
    sub OtterClient {
        return $cl ||= _make_Client();
    }
}

sub _make_Client {
    local @ARGV = ();
    Bio::Otter::Lace::Defaults::do_getopt();
    return Bio::Otter::Lace::Defaults::make_Client();
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

    my $iia = rowhash
      ($dbh, 'select * from job j
 join input_id_analysis iia using (input_id, analysis_id)
 join analysis a using (analysis_id)
 limit 1');
    push @type, 'pipe' if field_exist(runhost => $iia);

    my $proj_acc = rowhash
      ($dbh, 'select * from sequence
 join project_dump using (seq_id)
 join project_acc using (sanger_id)
 limit 1');
    push @type, 'submissions' if field_exist(htgs_phase => $proj_acc);

    return join ':', sort @type;
}


main();
