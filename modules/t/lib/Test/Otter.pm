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

use Sys::Hostname 'hostname';

use base 'Exporter';
our @EXPORT_OK = qw( db_or_skipall );


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

    # Else - need to skip the test
    Test::More::plan skip_all => "Direct database access not expected to work from $host - set WTSI_INTERNAL=1 to try";
    # it exits
    # (or if absent falls over in a heap, job done)

    return (); # not reached
}


=head1 CAVEATS

L</mods_rel> may be fragile in the face of chdir(2), but could be
fixed to deal with that.

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
