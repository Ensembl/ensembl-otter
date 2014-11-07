
### Bio::Otter::Source::BigWig

package Bio::Otter::Source::BigWig;

use strict;
use warnings;

use base 'Bio::Otter::Source::BigFile';

sub script_name { return 'bigwig_get'; }
sub zmap_style  { return 'heatmap';    }

1;

__END__

=head1 NAME - Bio::Otter::Source::BigWig

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

