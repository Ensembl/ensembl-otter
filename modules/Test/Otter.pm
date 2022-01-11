=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Test::Otter;
use strict;
use warnings;

=head1 NAME

Test::Otter - test setup boilerplate for ensembl-otter

=head1 SYNOPSIS

 # do something to ensure ensembl-otter/modules/ is on @INC

 # don't need to mess with FindBin or use lib
 use Test::Otter;

=head1 DESCRIPTION

The aim of this module is to move most of the boilerplate code out of
test scripts.

=head2 What C<use Test::Otter> does

=over 4

=item * Ensure that C<t/lib/> is on C<@INC>

Other modules related to testing can be left out of the main tree.

=item * Import tags with a C<^> prefix are shortcuts to run the named
subroutine.

They are run from this package, before the import happens.

=item * Import to caller's namespace continues with L<Exporter>.

Nothing is imported by default.

=back

=cut

use Carp;
use Sys::Hostname 'hostname';
use Try::Tiny;
use Test::Requires;

use parent qw(Exporter Test::Builder::Module);

our @EXPORT_OK = qw( db_or_skipall
                     data_dir_or_skipall
                     farm_or_skipall
                     OtterClient
                     get_BOLDatasets get_BOSDatasets
                     diagdump try_err
                     excused );


sub import {
    my ($pkg, @tag) = @_;

    $pkg->_ensure_tlib;

    $pkg->_quiet_require_BOG; # I think we always want this..?

    # run some
    my @imp_tag;
    foreach my $t (@tag) {
        if ($t =~ /^\^(.*)$/) {
            my $name = $1;
            die "Run-tag $t is not in EXPORT_OK (@EXPORT_OK)"
              unless grep { $_ eq $name } @EXPORT_OK;
            $pkg->$name;
            # POD says "runs".  How isn't important, class method is neater.
        } else {
            push @imp_tag, $t;
        }
    }

    # export the remainder
    return $pkg->export_to_level(1, $pkg, @imp_tag);
}


sub _ensure_tlib {
    # Be able to find other test modules
    require lib;
    my $fn = Test::Otter->proj_rel('t/lib');
    lib->import($fn);

    return ();
}

sub _quiet_require_BOG {
    local $SIG{__WARN__} = \&__BOG_warn_filter;
    if ($INC{'Bio/Otter/Git.pm'}) {
        warn "_quiet_require_BOG: too late!  Load T:O before B:O:G (maybe B:O:L:C)";
    } else {
        require Bio::Otter::Git;
    }
    return;
}
sub __BOG_warn_filter {
    my ($msg) = @_;
    return if $msg eq "No git cache: assuming a git checkout.\n";
    warn "[__BOG_warn_filter passed] $msg";
    return;
}


=head2 excused($test_sub, \@tree, @arg)

Wrapper to run a test comparison with an excuse.  Looks up in
L</excuses> using C<@tree> as keys into nested hashes, and sets
C<local $TODO> to the result.  Finds code for subroutine
C<${caller}::$test_sub>.  Calls it with C<@arg, $tree[-1]>.

Returns (scalar test result || excuse).

When formulating C<@arg> beware the lack of the prototypes provided by
the original subs.

This wrapper takes measures to "pass the stacktrace buck" for L<Carp>
and L<Test::Builder>, but C<caller>-based warning and error messages
will blame the wrong place.

=cut

sub excused {
    my ($test_sub, $tree, @arg) = @_;

    croak "Need keys for the hash-tree" unless try { scalar @$tree };
    my $excuse = __PACKAGE__->excuses();
    foreach my $ele (@$tree) {
        $excuse = try {
            $excuse->{$ele}
        } catch {
            # path @$tree is too long OR excuses structure is broken
            local $" = "', '";
            $excuse = '(undef)' unless defined $excuse;
            die "Bad excuse tree ['@$tree'] => '$excuse'->{'$ele'}: $_";
        };
        last unless defined $excuse;
    }
    if (ref($excuse) eq 'HASH') {
        # it seems the given path @$tree is too short
        local $" = "', '";
        die "Incomplete excuse tree ['@$tree'] => $excuse";
    }

    my $caller_pkg = caller();

    my $code = $caller_pkg->can($test_sub)
      or croak "Subroutine ${caller_pkg}::$test_sub not found";

    ## no critic(Variables::ProhibitPackageVars) for use of $Test::Builder::Level
    my $todo_pkg = caller($Test::Builder::Level-1); # trickyness; $Level is probably 1
    # warn "Use \$${todo_pkg}::TODO for Level=$Test::Builder::Level\n";

    my $name = $tree->[-1];

    my $result = do {
        # pass the stacktrace buck to $code
        local $Carp::Internal{ (__PACKAGE__) } = 1;
        local $Test::Builder::Level = $Test::Builder::Level + 1;

        # Test::Builder would find our $TODO, except we bumped the level
        my $varname = $todo_pkg.'::TODO';
        no strict 'refs'; ## no critic(TestingAndDebugging::ProhibitNoStrict)
        local ${ $varname } = $excuse ? "excused: $excuse" : undef;
        use strict 'refs';

        $code->(@arg, $name);
    };

#    diagdump(tree => $tree, excuse => $excuse, caller_pkg => $caller_pkg)
#      unless $result;

    return $result || $excuse
}


=head1 CLASS METHODS

=head2 proj_rel($path)

Return C<< .../ensembl-otter/$path >> by reference to the filename of
this module.

=cut

sub proj_rel {
    my ($pkg, $path) = @_;
    my $fn = __FILE__;
    $fn =~ s{(^|/)(?:modules|lib)/Test/Otter\.pm$}{$1}
      or die "Couldn't make \$PROJ/$path name from $fn";
    return "${fn}${path}";
}


=head2 cachedir()

Return a directory which exists and is writable, and can be used for
caching stuff between tests.  Files written inside should be 0664.

Has a list of preferences and a fallback.  Could probably use some
environment variable to choose team-shared vs. developer, and
permanence.  If the directory is not being shared, make it private.

=cut

sub cachedir {
    my ($pkg) = @_;
    my @dir = ("$ENV{HOME}/t-cache/ensembl-otter",
               '/nfs/anacode/t-cache/ensembl-otter');
    @dir = grep { -d $_ && -w _ } @dir;
    if (!@dir) {
        my $fn = $pkg->proj_rel('t-cache~'); # is git-ignore'd
        # my $fn = '/tmp/t-cache.ensembl-otter'

        if (-e $fn) {
            die "$fn exists and is not yours, can't mkdir"
              unless -d _ && -O _ && -w _;
        } else {
            mkdir $fn, 0700
              or die "mkdir $fn: $!";
        }
        push @dir, $fn;
    }
    return $dir[0];
}


=head2 excuses()

Load, cache and return a hashref for the "excused" test failures.  See
also L</excused>.  The purpose is not to skip the test, but to run it
expecting failure because "we know that is broken".

Top level is a test name, further levels are some test-specific
detail.

Data comes from team_tools.git and is used to downgrade test failures
into TODOs.  Tests should consider it read-only; auto-vivification
will cause confusion.

Generates a warning if the data can't be loaded, then returns C< {} >.

=cut

my $_excuses;
sub excuses {
    my ($pkg) = @_;
    require YAML;
    return $_excuses ||= try {
        die '$ANACODE_TEAM_TOOLS not available' unless -d $ENV{ANACODE_TEAM_TOOLS};
        YAML::LoadFile("$ENV{ANACODE_TEAM_TOOLS}/config/test-excuses.yaml");
    } catch {
        my $msg = $_;
        $msg =~ s{^}{  }mg;
        warn "$pkg->excuses returns nothing, continue without.\n$msg";
        {};
    };
}


=head1 EXPORTABLE SUBROUTINES

=head2 db_or_skipall()

If it thinks you have direct access to internal databases, returns
nothing.

Otherwise it will skip the entire test.

This works nicely with C<< use Test::Otter qw( ^db_or_skipall ); >>.

=cut

sub db_or_skipall {

    test_requires('DBD::mysql');

    my $error = check_db();
    return unless $error;

    return _skipall($error);
}

# Factored out for the benefit of 00_FailBulkSkips.t
# Silence is golden.
#
sub check_db {
    my $host = hostname(); # is not FQDN on my deskpro
    return if ( $host =~ /\.sanger\.ac\.uk$/
                || -d "/software/anacode"
                || $ENV{WTSI_INTERNAL}
        );
    return "Direct database access not expected to work from $host - set WTSI_INTERNAL=1 to try";
}

sub _skipall {
    my ($why) = @_;
    my $builder = __PACKAGE__->builder;
    $builder->skip_all($why);
    # it exits
    # (or if absent falls over in a heap, job done)

    return (); # not reached
}


=head2 farm_or_skipall()

If it thinks you are on Farm2, returns nothing.

Otherwise it will skip the entire test.

TODO: C<exec ssh farm2-login> if you're not, reproducing sufficient
Perl environment, and then continue.

=cut

sub farm_or_skipall {
    return () if -d '/lustre';
    my $host = hostname(); # is not FQDN on my deskpro
    return _skipall("Test expects to run on Farm2, but is on $host");
}


=head2 data_dir_or_skipall

If it thinks the otter data directory can be found, returns nothing.

Otherwise it will skip the entire test.

=cut

sub data_dir_or_skipall {
    my $error = check_data_dir();
    return unless $error;

    return _skipall($error);
}

# Factored out for the benefit of 00_FailBulkSkips.t
# Silence is golden.
#
sub check_data_dir {
    return try {
        require Bio::Otter::Server::Config;
        my $data_dir = Bio::Otter::Server::Config::data_dir();
        my $builder = __PACKAGE__->builder;
        $builder->note("data_dir: '$data_dir'");
        return;                     # ok
    } catch {
        my $error = $_;
        return "Test cannot find otter data_dir: '$error'";
    };
}

=head2 OtterClient()

Caches and returns a L<Bio::Otter::Lace::Client> made with no extra
parameters.

=head2 get_BOLDatasets(@name), get_BOSDatasets(@name)

These wrap up L<Bio::Otter::Lace::Defaults/make_Client> and
L<Bio::Otter::Server::Config/SpeciesDat> to return a list of datasets.

The requested dataset object is returned C<foreach @name>.

For C<get_BOLDatasets>, the methods C<get_cached_DBAdaptor> and
C<get_pipeline_DBAdaptor> give the loutre and pipe databases.

For C<get_BOSDatasets>, the methods C<otter_dba> and C<pipeline_dba>
do it.  There is also C<satellite_dba>.

If C<"@name" eq "ALL"> then all available species are used.  The
server mode does no filtering, but the client mode may hide
C<human_dev> etc. depending which user you seem to be.

Further tags like C<ALL_UNLISTED> would be useful, allowing for
restricted and unlisted datasets.

See also F<t/obtain-db.t>

=cut

{
    my $cl_cache;
    sub OtterClient {
        return $cl_cache ||= do {
            local @ARGV = ();
            require Bio::Otter::Lace::Defaults;
            local $SIG{__WARN__} = \&__BOLC_warn_filter; # hide client startup noise
            Bio::Otter::Lace::Defaults::do_getopt();
            my $cl = Bio::Otter::Lace::Defaults::make_Client();

            # Test scripts shall not request user password
            my $no_pass = sub {
                my ($self) = @_;
                warn "$self: wanted your password.  Run live otter to get a cookie!\n";
                return;
            };
            $cl->password_prompt($no_pass);

            $cl; # no 'return' from 'do'
        };
    }
}

sub get_BOLDatasets {
    my @name = @_;
    my $cl = OtterClient();
    warn "No datasets requested" unless @name;
    die "wantarray" unless wantarray;
    return $cl->get_all_DataSets if "@name" eq 'ALL';
    return map { $cl->get_DataSet_by_name($_) } @name;
}

sub get_BOSDatasets {
    my @name = @_;
    require Bio::Otter::Server::Config;
    my $bosc_sd = Bio::Otter::Server::Config->SpeciesDat;
    warn "No datasets requested" unless @name;
    die "wantarray" unless wantarray;
    return $bosc_sd->all_datasets if "@name" eq 'ALL';
    return map { $bosc_sd->dataset($_) or die "No such dataset '$_'" } @name;
}

sub __BOLC_warn_filter { # a "temporary" solution
    my ($msg) = @_;
    return if $msg =~ m{^Debug from config: '[a-zA-Z,]+'$};
    return if $msg =~ m{^setup_pfetch_env: hostname=};
    return if $msg =~ m{^DEBUG: (CLIENT|ZIRCON|XREMOTE) = 1\n\z};
    return if $msg =~ m{^GET  http.*/get_datasets\?|^get_datasets - client received \d+ bytes from server};
    warn "[__BOLC_warn_filter passed] $msg";
    return;
}



=head2 diagdump(%info)

Shortcut for L<Test::More/diag> with L<YAML/Dump>, as in

 is(scalar @stuff, 1, 'no dup stuff') or
   diagdump(stuff => \@stuff);

=cut

sub diagdump {
    my %info = @_;
    require YAML;
    return main::diag YAML::Dump(\%info);
}


=head2 try_err { ... }

Shortcut for

 try { ... } catch { "ERR:$_" };

which is a useful fit with the C<like> assertion.

=cut

# XXX:DUP same as zircon.git lib/TestShared.pm
sub try_err(&) { ## no critic (Subroutines::ProhibitSubroutinePrototypes)
    my ($code) = @_;
    return try { $code->() } catch { "ERR:$_" };
}


=head1 CAVEATS

L</proj_rel> may be fragile in the face of chdir(2), but could be
fixed to deal with that.

L</diagdump> assumes the caller is in C<main::> and used
L<Test::More>.


=head1 AUTHOR

Matthew Astley mca@sanger.ac.uk

=cut


1;
