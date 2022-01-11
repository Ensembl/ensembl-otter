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

# Regexps for detainting config stuff

package Bio::Vega::Utils::Detaint;

use strict;
use warnings;

use Carp;
use Readonly;

use base 'Exporter';
our @EXPORT_OK = qw{ detaint_url_fmt detaint_pfam_url_fmt detaint_sprintfn_url_fmt };

Readonly my $url_chrs    => qr{[-=_:?/\\.a-zA-Z0-9]};
Readonly my $url_sprintf => qr{^(http${url_chrs}+\%s${url_chrs}*)$}o;

my $url_pfam_str = $url_sprintf;
$url_pfam_str =~ s/\%s/\%(?:s|\{pfam\})/; # substitution destroys qr propery, so...
Readonly my $url_pfam => qr{$url_pfam_str}o;

# Allow Text::sprintfn format strings
Readonly my $url_sprintfn => qr{
    ^ (                         # match and capture whole string
        http${url_chrs}+        # start with http and some URL stuff
        (?:                     # one or more repeats of:
          \%\(\w+\)s            #   a sprintfn %(key)s named string field
          ${url_chrs}*          #   and maybe some more URL stuff
        )+
    ) $
}ox;

# Functions, not methods!

sub detaint_url_fmt {
    my ($url_fmt) = @_;
    my ($result) = ($url_fmt =~ m{$url_sprintf});
    return $result;
}

sub detaint_pfam_url_fmt {
    my ($url_fmt) = @_;
    my ($result) = ($url_fmt =~ m{$url_pfam});
    return $result;
}

sub detaint_sprintfn_url_fmt {
    my ($url_fmt) = @_;
    my ($result) = ($url_fmt =~ m{$url_sprintfn});
    return $result;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

