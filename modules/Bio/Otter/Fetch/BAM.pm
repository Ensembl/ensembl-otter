
### Bio::Otter::Fetch::BAM

package Bio::Otter::Fetch::BAM;

use strict;
use warnings;

use Carp;

sub new {
    my ($pkg, @args) = @_;
    return bless { @args }, $pkg;
}

sub features {
    my ($self, $chr, $start, $end) = @_;

    my ( $sam, $chr_prefix ) =
        @{$self}{qw( -sam -chr_prefix )};

    $chr = "${chr_prefix}${chr}" if defined $chr_prefix;
    my $features = [
        $sam->features(
            -type   => 'match',
            -seq_id => $chr,
            -start  => $start,
            -end    => $end,
        )
    ];
    warn sprintf "found %d matches\n", scalar @$features;

    return $features;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

