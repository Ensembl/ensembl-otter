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
