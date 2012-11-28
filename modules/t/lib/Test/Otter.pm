package Test::Otter;
use strict;
use warnings;

=haed1 NAME

Test::Otter - test setup boilerplate for ensembl-otter

=head1 SYNOPSIS

 # do something to ensure ensembl-otter/modules/ is on @INC
 
 # don't need to mess with FindBin or use lib
 use t::lib::Test::Otter;

=head1 DESCRIPTION

The aim of this module is to move most of the boilerplate code out of
test scripts.

=head2 What C<use t::lib::Test::Otter> does

On the assumption that the F<t/lib/> directory was not already on
C<@INC>, add it.

The C<%INC> entry for L<Test::Otter> is set, so it may then be C<use>d
again by the real name.

Import then continues as for C<use Test::Otter>.

=head2 What C<use Test::Otter> does

=over 4

=item * Import tags with a C<^> prefix are shortcuts to run the named
subroutine.

=item * Import to caller's namespace continues with L<Exporter>.

Nothing is imported by default.

=back

=cut

use Carp;
use Sys::Hostname 'hostname';
use Try::Tiny;

use base 'Exporter';
our @EXPORT_OK = qw( db_or_skipall farm_or_skipall OtterClient get_BOLDatasets diagdump excused );


sub import {
    my ($pkg, @tag) = @_;

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


=head2 excused($test_sub, \@tree, @arg)

Wrapper to run a test comparison with an excuse.  Looks up in
L</excuses> using C<@tree> as keys into nested hashes, and sets
C<local $TODO> to the result.  Finds code for subroutine
C<${caller}::$test_sub>.  Calls it with C<@arg, $tree[-1]>.

Returns (scalar test result || excuse).

When formulating C<@arg> beware the lack of the prototypes provided by
the original subs.

=cut

our $TODO;
sub excused {
    my ($test_sub, $tree, @arg) = @_;
    my $caller_pkg = caller();

    croak "Need keys for the hash-tree" unless eval { scalar @$tree };
    my $code = $caller_pkg->can($test_sub)
      or croak "Subroutine ${caller_pkg}::$test_sub not found";

    my $excuse = __PACKAGE__->excuses();
    foreach my $ele (@$tree) {
        $excuse = try {
            $excuse->{$ele}
        } catch {
            local $" = "', '";
            $excuse = '(undef)' unless defined $excuse;
            die "Bad excuse tree ['@$tree'] => '$excuse'->{'$ele'}: $_";
        };
        last unless defined $excuse;
    }

    my $name = $tree->[-1];

    local $TODO = $excuse; # caller() is used find our $TODO, not $main::TODO
    my $result = $code->(@arg, $name);

#    diagdump(tree => $tree, excuse => $excuse, caller_pkg => $caller_pkg)
#      unless $result;

    return $result || $excuse
}


=head1 CLASS METHODS

=head2 mods_rel($path)

Return C<< .../ensembl-otter/modules/$path >> by reference to the
filename of this module.

=cut

sub mods_rel {
    my ($pkg, $path) = @_;
    my $fn = __FILE__;
    $fn =~ s{/t/lib/Test/Otter\.pm$}{}
      or die "Couldn't make modules/ name from $fn";
    return "$fn/$path";
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
        my $fn = $pkg->mods_rel('../t-cache~'); # is git-ignore'd
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

Otherwise it will skip the entire test - with a clean skip and C<exit>
if L<Test::More> is loaded, else with an error.

This works nicely with C<< use Test::Otter qw( ^db_or_skipall ); >>.

Do it after C<< use Test::More >> or fix it to cope.

=cut

sub db_or_skipall {
    warn "Currently assuming Test::More is loaded - it isn't"
      unless $INC{'Test/More.pm'};

    my $host = hostname(); # is not FQDN on my deskpro
    return () if ($host =~ /\.sanger\.ac\.uk$/
                  || -d "/software/anacode"
                  || $ENV{WTSI_INTERNAL});

    return _skipall("Direct database access not expected to work from $host - set WTSI_INTERNAL=1 to try");
}

sub _skipall {
    my ($why) = @_;
    Test::More::plan(skip_all => $why);
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


=head2 OtterClient()

Caches and returns a L<Bio::Otter::Lace::Client> made with no extra
parameters.

=head2 get_BOLDatasets(@name)

This wraps up L<Bio::Otter::Lace::Defaults/make_Client> to return a
list of datasets.

The requested L<Bio::Otter::Lace::DataSet> object is returned for each
element of C<@name>. Methods C<get_cached_DBAdaptor> and
C<get_pipeline_DBAdaptor> give the loutre and pipe databases.

If C<"@name" eq "ALL"> then all published species are used.  This
won't include C<human_dev> etc..

Defining C<get_BOSDatasets> for L<Bio::Otter::SpeciesDat::DataSet> may
be better but is not yet implemented.  Equivalent methods are named
C<otter_dba> and C<pipeline_dba>, there is also C<satellite_dba>.

Further tags like C<ALL_UNLISTED> would be useful, allowing for
restricted and unlisted datasets.

=cut

{
    my $cl;
    sub OtterClient {
        return $cl ||= do {
            local @ARGV = ();
            require Bio::Otter::Lace::Defaults;
            Bio::Otter::Lace::Defaults::do_getopt();
            Bio::Otter::Lace::Defaults::make_Client();
        };
    }
}

sub get_BOLDatasets {
    my @name = @_;
    my $cl = OtterClient();
    warn "No datasets requested" unless @name;
    return $cl->get_all_DataSets if "@name" eq 'ALL';
    return map { $cl->get_DataSet_by_name($_) } @name;
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


=head1 CAVEATS

L</mods_rel> may be fragile in the face of chdir(2), but could be
fixed to deal with that.

L</diagdump> assumes the caller is in C<main::> and used
L<Test::More>.


=head1 AUTHOR

Matthew Astley mca@sanger.ac.uk

=cut



package t::lib::Test::Otter; ## no critic (Modules::ProhibitMultiplePackages)
#
# This package is the "bogus twin", merely Test::Otter by a longer
# path through the filesystem.
#
# The choice of t/lib/ over t/tlib/ was arbitrary, but dictates our
# packagename.

sub import { ## no critic (Subroutines::RequireArgUnpacking)
    my ($pkg, @tag) = @_;

    # Make it clear the "good twin" is also present.
    $INC{'Test/Otter.pm'} = __FILE__; ## no critic (Variables::RequireLocalizedPunctuationVars)

    # Be able to find "good twin"'s siblings.
    require lib;
    my $fn = Test::Otter->mods_rel('t/lib');
    lib->import($fn);

    # goto make export_to_level simpler
    @_ = ('Test::Otter', @tag);
    goto &Test::Otter::import;;
}


1;
