
### Bio::Vega::Utils::URI

package Bio::Vega::Utils::URI;

use strict;
use warnings;
use URI::Escape qw{ uri_escape };

use base 'Exporter';

our @EXPORT_OK = qw{ open_uri };

sub open_uri {
    my ($path, $param_hash) = @_;

    my $command = $^O eq 'darwin' ? 'open' : 'xdg-open';

    my $form = '';
    if ($param_hash) {
        $form = '?' . join('&', map { "$_=" . uri_escape($param_hash->{$_}) } keys %$param_hash);
    }
    return system($command, $path . $form) == 0;
}


1;

__END__

=head1 NAME - Bio::Vega::Utils::URI

=head1 EXAMPLE

    my $success = open_uri('mailto:jgrg@sanger.ac.uk',
        {
            subject => "A test & other & stuff",
            body    => "Some very interesting text & stuff\nin here over several\nlines.",
        });

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

