package Bio::Otter::Lace::OnTheFly::Utils::ExonerateFormat;

use strict;
use warnings;

use Readonly;

use Bio::Otter::Vulgar;

use base qw( Exporter );
our @EXPORT_OK = qw( ryo_format ryo_order sugar_order );

# These must match
#
Readonly my $RYO_FORMAT => 'RESULT: %S %pi %ql %tl %g %V\n';
Readonly my @RYO_ORDER => (
    '_tag',
    @Bio::Otter::Vulgar::SUGAR_ORDER,
    qw(
        _perc_id
        _query_length
        _target_length
        _gene_orientation
      ),
);

sub ryo_format  { return $RYO_FORMAT; }
sub ryo_order   { return @RYO_ORDER;  }
sub sugar_order { return @Bio::Otter::Vulgar::SUGAR_ORDER; }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
