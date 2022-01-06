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

#module to escape special characters embedded in a string xml value

package Bio::Vega::Utils::XmlEscape;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ xml_escape xml_unescape };

sub xml_escape {

    my $str = shift;
    # Must do ampersand first!
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&apos;/g;
    return $str;
}

sub xml_unescape {

    my $str = shift;
    $str =~ s/&apos;/'/g;
    $str =~ s/&quot;/"/g;
    $str =~ s/&gt;/>/g;
    $str =~ s/&lt;/</g;
    # Must do ampersand last!
    $str =~ s/&amp;/&/g;
    return $str;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

