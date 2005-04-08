package Evi::ScaleFitwidth;

# Re-scales the everything to fit into given width
#
# lg4, 28.Feb'2005

use base ('Evi::ScaleBase');

sub def_unit { # to make it overridable; in this class it is the visible width
    return 1000;
}

sub scale_point {
	my $self  = shift @_;
	my $point = shift @_;

	$self->rescale_if_needed();

	my $mapped = $self->unit()*($point-$self->{_min})/($self->{_max}-$self->{_min});
	return $mapped;
}

1;
