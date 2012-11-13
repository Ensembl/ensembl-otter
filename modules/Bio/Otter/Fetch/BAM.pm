
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

    my $sam = $self->sam;
    my $seq_id = $self->seq_id_from_chr($chr);

    my $features = [
        $sam->features(
            -type   => 'match',
            -seq_id => $seq_id,
            -start  => $start,
            -end    => $end,
        )
    ];
    warn sprintf "found %d matches\n", scalar @$features;

    return $features;
}

# The seq_ids in many BAM files prepend "chr" to the name of the
# chromosome so we look for both "$chr" and "chr${chr}".

sub seq_id_from_chr {
    my ($self, $chr) = @_;

    my $seq_id_hash = { };
    $seq_id_hash->{$_}++ for $self->sam->seq_ids;
    for ( $chr, "chr${chr}" ) {
        return $_ if $seq_id_hash->{$_};
    }

    croak sprintf "no such seq_id: '%s'", $chr;
}

# attributes

sub sam {
    my ($self) = @_;
    my $sam = $self->{'-sam'};
    return $sam;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

