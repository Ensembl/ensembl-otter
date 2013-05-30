
### Bio::Otter::Utils::Constants

package Bio::Otter::Utils::Constants;

use strict;
use warnings;

use Readonly;

Readonly my $INTRON_MINIMUM_LENGTH => 30;

use base 'Exporter';
our @EXPORT_OK = qw( intron_minimum_length );

sub intron_minimum_length { return $INTRON_MINIMUM_LENGTH; }

1;

__END__

=head1 NAME - Bio::Otter::Utils::Constants

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
