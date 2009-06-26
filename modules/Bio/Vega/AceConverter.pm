
### Bio::Vega::AceConverter

package Bio::Vega::AceConverter;

use strict;
use warnings;
use Carp qw{ cluck confess };

use Hum::Ace::AceText;
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'method2biotype_status';

my %ace2ens_phase = (
    1   => 0,
    2   => 2,
    3   => 1,
    );



1;

__END__

=head1 NAME - Bio::Vega::AceConverter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

