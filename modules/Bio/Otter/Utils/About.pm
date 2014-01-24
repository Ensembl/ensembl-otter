package Bio::Otter::Utils::About;
use strict;
use warnings;

use Bio::Otter::Git;
use Bio::Otter::Lace::Client;
use Try::Tiny;
use Bio::EnsEMBL::ApiVersion ();


=head1 NAME

Bio::Otter::Utils::About - generate text telling version info

=head1 DESCRIPTION

Obtain user-friendly information about the tools' versions.

=head1 CLASS METHODS

=head2 about_text()

Return multi-line text containing version number(s), source
configuration info and URL(s).

=cut

sub about_text {
    my ($pkg) = @_;

    my $vsn = Bio::Otter::Git->as_text;
    my $anno = join '', map {"  $_\n"}
      try { $pkg->tools_versions() }
        catch { "some parts broken: $_" };

    my ($vsn_zircon, $vsn_perlmod, $vsn_cliens) = map
      { Bio::Otter::Git->dist_conf($_) }
        qw( zircon PerlModules client_ensembl_version );

    return <<"TEXT";
This is Otterlace version $vsn

Otterlace web page
  http://www.sanger.ac.uk/resources/software/otterlace/

Contains\n${anno}Client Ensembl from $vsn_cliens
PerlModules from $vsn_perlmod
Zircon from $vsn_zircon
TEXT
}


=head2 tools_versions()

Return a list of strings describing tools to be called.

Dies if any tool will not run and provide its version.

=cut

sub tools_versions {
    my @prog = __need_tools();
    my @v;
    foreach my $tool (@prog) {
        my ($prog, $opt, $filter) = @$tool;
        my @cmd = ($prog, $opt);
        open my $fh, '-|', @cmd
          or die "Failed to pipe from '@cmd': $!\n";
        my $txt = do { local $/ = undef; <$fh> }; # slurp
        my $fail;
        if ($filter) {
            my $orig = $txt;
            ($txt) = $txt =~ $filter
              or $fail = "No version =~ $filter in ''$orig''";
        }
        unless (close $fh) {
            if ($!) {
                $fail = "Error closing pipe: $!";
            } elsif ($? & 127) {
                $fail = "Killed by sig $?";
            } else {
                $fail = "Exit code ".($? >> 8)
                  unless $filter;
            }
        }
        die "Command '@cmd' failed, $fail\n" if defined $fail;

        open $fh, '-|', which => $prog
          or die "Failed to pipe from 'which': $!\n";
        my $which = do { local $/ = undef; <$fh> }; # slurp
        close $fh; # ignore exit

        chomp ($txt, $which);
        push @v, "$txt from $which";
    }

    push @v, sprintf('Client EnsEMBL %s from %s',
                     Bio::EnsEMBL::ApiVersion::software_version(),
                     $INC{'Bio/EnsEMBL/ApiVersion.pm'});

    my $client = Bio::Otter::Lace::Client->the;
    push @v, sprintf('Server EnsEMBL %s',
                     $client->get_server_ensembl_version); # cached
    # we may have blocked for a while,
    # but probably not failed because a) it's cached and b) it is
    # requested at startup right after an authentication check

    return @v;
}

sub __need_tools {
    return
      ([ zmap => '--version' ],
       [ blixemh => '--version' ], # represents other Seqtools
       [ sgifaceserver => '-version',
         qr{^(acedb \S+),}i ],

       # EditWindow::Preferences uses 'open -e' on Mac

       [ exonerate => '--version', # Bio::Otter::Lace::OnTheFly::Aligner
         qr{(exonerate version .*)} ],

       [ hmmalign => '-h', # Bio::Otter::Lace::Pfam
         qr{(HMMER\s+\d\S+)}im ],

       # EditWindow::PfamWindow
       # [ belvu => '--version' ], # part of Seqtools

       [ filter_get => '--version' ], # Bio::Otter::Filter

       [ gff_get => '--version' ],
       [ bam_get => '--version' ],
       [ bigwig_get => '--version' ],
      );
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
