
### Bio::Otter::GappedAlignment

package Bio::Otter::GappedAlignment;

use strict;
use warnings;

use Bio::Otter::GappedAlignment::Element;

use Readonly;

# FIXME: also in Bio::Otter::Lace::OnTheFly::Aligner
Readonly our @SUGAR_ORDER => qw(
    _query_id
    _query_start
    _query_end
    _query_strand
    _target_id
    _target_start
    _target_end
    _target_strand
    _score
);

sub _new {
    my ($pkg, %sugar) = @_;

    my $self = bless { %sugar }, $pkg;
    $self->_clear_elements;

    return $self;
}

sub from_vulgar {
    my ($pkg, $vulgar) = @_;

    my @vulgar_parts = split(' ', $vulgar);
    my (%sugar_result, @vulgar_comps);
    (@sugar_result{@SUGAR_ORDER}, @vulgar_comps) = @vulgar_parts;

    # FIXME: error handling on %sugar_result

    my $self = $pkg->_new(%sugar_result);

    while (@vulgar_comps) {
        my ($type, $q_len, $t_len) = splice(@vulgar_comps, 0, 3); # shift off 1st three
        unless ($type and defined $q_len and defined $t_len) {
            die "Ran out of vulgar components in mid-triplet";
        }
        my $element = Bio::Otter::GappedAlignment::Element->new($type, $q_len, $t_len);
        $self->add_element($element);
    }

    return $self;
}

# FIXME: which of these should be r/w vs r/o ?

sub query_id {
    my ($self, $query_id) = @_;
    if ($query_id) {
        $self->{'_query_id'} = $query_id;
    }
    return $self->{'_query_id'};
}

sub query_start {
    my ($self, $query_start) = @_;
    if ($query_start) {
        $self->{'_query_start'} = $query_start;
    }
    return $self->{'_query_start'};
}

sub query_end {
    my ($self, $query_end) = @_;
    if ($query_end) {
        $self->{'_query_end'} = $query_end;
    }
    return $self->{'_query_end'};
}

sub query_strand {
    my ($self, $query_strand) = @_;
    if ($query_strand) {
        $self->{'_query_strand'} = $query_strand;
    }
    return $self->{'_query_strand'};
}

sub target_id {
    my ($self, $target_id) = @_;
    if ($target_id) {
        $self->{'_target_id'} = $target_id;
    }
    return $self->{'_target_id'};
}

sub target_start {
    my ($self, $target_start) = @_;
    if ($target_start) {
        $self->{'_target_start'} = $target_start;
    }
    return $self->{'_target_start'};
}

sub target_end {
    my ($self, $target_end) = @_;
    if ($target_end) {
        $self->{'_target_end'} = $target_end;
    }
    return $self->{'_target_end'};
}

sub target_strand {
    my ($self, $target_strand) = @_;
    if ($target_strand) {
        $self->{'_target_strand'} = $target_strand;
    }
    return $self->{'_target_strand'};
}

sub score {
    my ($self, $score) = @_;
    if ($score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'};
}

sub elements {
    my $self = shift;
    return $self->{'_elements'};
}

sub add_element {
    my ($self, $element) = @_;
    push @{$self->elements}, $element;
    return $self->elements;
}

sub n_elements {
    my $self = shift;
    return scalar @{$self->elements};
}
    
sub _clear_elements {
    my $self = shift;
    return $self->{'_elements'} = [];
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
