package Bio::Otter::Utils::About;
use strict;
use warnings;

use Bio::Otter::Git;
use Try::Tiny;


=head1 NAME

Bio::Otter::Utils::About - generate text telling version info

=head1 DESCRIPTION

Obtain user-friendly information about the tools' versions.

=head1 CLASS METHODS

=head2 about_text()

Return multi-line text containing version number(s) and URL(s).

=cut

sub about_text {
    my ($pkg) = @_;

    my $vsn = Bio::Otter::Git->as_text;
    my $anno = join ', ', try { $pkg->annotools_versions() }
      catch { "some parts broken: $_" };

    return <<"TEXT";
This is Otterlace version $vsn
with $anno\n
Otterlace web page
  http://www.sanger.ac.uk/resources/software/otterlace/
TEXT
}


=head2 annotools_versions()

Return a list of strings describing tools to be called.

Dies if any tool will not run and provide its version.

=cut

sub annotools_versions {
    my @v;
    my @prog = qw( zmap ); # current blixemh writes to stderr with exitcode 1
    foreach my $prog (@prog) {
        my @cmd = ($prog, '--version');
        open my $fh, '-|', @cmd
          or die "Failed to pipe from '@cmd': $!\n";
        my $txt = do { local $/ = undef; <$fh> }; # slurp
        unless (close $fh) {
            my $fail;
            if ($!) {
                $fail = "Error closing pipe: $!";
            } elsif ($? & 127) {
                $fail = "Killed by sig $?";
            } else {
                $fail = "Exit code ".($? >> 8);
            }
            die "Command '@cmd' failed, $fail\n";
        }
        chomp $txt;
        push @v, $txt;
    }
    return @v;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
