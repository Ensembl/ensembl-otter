
### Bio::Otter::Source::BAM

package Bio::Otter::Source::BAM;

use strict;
use warnings;

use base 'Bio::Otter::Source::BigFile';

sub script_name { return 'bam_get';    }
sub zmap_style  { return 'short-read'; }

sub is_seq_data { return 1; }

sub parent_column {
    my ($self) = @_;
    return $self->{parent_column};
}

sub parent_featureset {
    my ($self) = @_;
    return $self->{parent_featureset};
}

sub coverage_plus {
    my ($self) = @_;
    return $self->{coverage_plus};
}

sub coverage_minus {
    my ($self) = @_;
    return $self->{coverage_minus};
}

1;

__END__

=head1 NAME - Bio::Otter::Source::BAM

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

