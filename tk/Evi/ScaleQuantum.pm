package Evi::ScaleQuantum;

# A scaler that uniformly orders points on a crude scale of indices,
# which becomes important for seeing the subtle differences between similar exon ends.
#
# lg4, 28.Feb'2005

use base ('Evi::ScaleBase');

sub def_unit { # to make it overridable; in this class it is the smallest difference
    return 10;
}

sub rescale_if_needed {
	my $self = shift @_;

	if($self->needs_rescaling()) {
		my $sortlist_lp = $self->get_sorted_points_lp();
		%{$self->{_indexmap}} = map { ($sortlist_lp->[$_] => $_) } (0..@$sortlist_lp-1);
		$self->needs_rescaling(0);
	}
}

sub scale_point {
	my $self  = shift @_;
	my $coord = shift @_;

	$self->rescale_if_needed();

	return $self->unit()*$self->{_indexmap}{$coord};
}

1;

