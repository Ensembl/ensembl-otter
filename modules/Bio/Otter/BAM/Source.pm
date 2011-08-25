
### Bio::Otter::BAM::Source

package Bio::Otter::BAM::Source;

use strict;
use warnings;

use Carp;

sub new {
    my ( $pkg, @args ) = @_;
    return bless { @args }, $pkg;
}

sub features {
    my ( $self, $chr, $start, $end ) = @_;

    my ( $sam, $chr_prefix ) =
        @{$self}{qw( -sam -chr_prefix )};

    $chr = "${chr_prefix}${chr}" if defined $chr_prefix;
    my @read_pairs = $sam->features(
        -type   => 'read_pair',
        -seq_id => $chr,
        -start  => $start,
        -end    => $end,
        );
    warn sprintf "found %d read pairs\n", scalar @read_pairs;

    my $features = [ map { $_->get_SeqFeatures } @read_pairs ];

    return $features;
}

1;

__END__

=head1 NAME - Bio::Otter::BAM::Source

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

