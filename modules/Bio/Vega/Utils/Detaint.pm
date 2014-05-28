# Regexps for detainting config stuff

package Bio::Vega::Utils::Detaint;

use strict;
use warnings;

use Carp;
use Readonly;

use base 'Exporter';
our @EXPORT_OK = qw{ detaint_url_fmt detaint_pfam_url_fmt };

Readonly my $url_chrs    => qr{[-=_:?/\\.a-zA-Z0-9]};
Readonly my $url_sprintf => qr{^(http${url_chrs}+\%s${url_chrs}*)$}o;

my $url_pfam_str = $url_sprintf;
$url_pfam_str =~ s/\%s/\%(?:s|\{pfam\})/; # substitution destroys qr propery, so...
Readonly my $url_pfam => qr{$url_pfam_str}o;

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

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

