=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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

    my (undef, undef, $desig_info) = $pkg->version_diagnosis();

    my ($vsn_zircon, $vsn_perlmod, $vsn_cliens) = map
      { Bio::Otter::Git->dist_conf($_) }
        qw( zircon PerlModules client_ensembl_version );

    my $dev_server =
      (Bio::Otter::Lace::Client->the->url_root_is_default
       ? ''
       : sprintf("  *** Non-standard URL root *** %s ***\n",
                 Bio::Otter::Lace::Client->the->url_root));

    # Extra info (beyond $anno) below can be found from log output or
    # the ensembl-otter commitid, so we only need to show it in GUI
    return <<"TEXT";
This is Otter version $vsn, $desig_info
$dev_server
Otter web page
  http://www.sanger.ac.uk/science/tools/otter

Contains\n${anno}Client Ensembl from $vsn_cliens
PerlModules from $vsn_perlmod
Zircon from $vsn_zircon
TEXT
}


=head2 version_diagnosis()

Returns a list C<(do_warn, colour, description)>
describing status of this software version.

=cut

sub version_diagnosis {
    my ($pkg) = @_;

    my $desig_info = Bio::Otter::Lace::Client->the->designate_this;
    my ($desig, $descr, $stale) =
      @{$desig_info}{qw{ major_designation descr stale }};

    # Ugly trick to direct tickets, for dev/otter_this and testers on MacOS
    $ENV{OTTER_RAN_AS} = "inferred/otter_$desig"
      if defined $desig && !defined $ENV{OTTER_RAN_AS};

    my %colour = ( live => 'white',
                   test => '#a1e3c9', # slightly minty
                   dev => '#fb9f4a', #f4cb9f',
                   old => 'pink',
                   _designated => 'pink',
                   _obsolete => 'red');
    my $colour = $colour{ $desig || '_obsolete' };
    $colour = $colour{_designated} if defined $desig && !$colour;

    return ($stale, $colour, $descr);
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

    push @v, sprintf('ensembl-otter from %s', $INC{'Bio/Otter/Version.pm'});

    push @v, sprintf('ZMQ::LibZMQ3 v%s from %s',
                     $ZMQ::LibZMQ3::VERSION, $INC{'ZMQ/LibZMQ3.pm'})
      if defined $ZMQ::LibZMQ3::VERSION;

    push @v, sprintf('Tk v%s from %s', $Tk::VERSION, $INC{'Tk.pm'});

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
      ([ zmap => '--raw_version' ],
       [ blixemh => '--version' ], # represents other Seqtools

       # EditWindow::Preferences uses 'open -e' on Mac

       [ exonerate => '--version', # Bio::Otter::Lace::OnTheFly::Runner
         qr{(exonerate version .*)} ],

       [ hmmalign => '-h', # Bio::Otter::Lace::Pfam
         qr{(HMMER\s+\d\S+)}im ],

       # EditWindow::PfamWindow
       # [ belvu => '--version' ], # part of Seqtools

       [ filter_get => '--version' ], # Bio::Otter::Source::Filter

       [ gff_get => '--version' ],
       [ bam_get => '--version' ],
       [ bigwig_get => '--version' ],
      );
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
