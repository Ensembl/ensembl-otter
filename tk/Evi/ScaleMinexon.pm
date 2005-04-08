package Evi::ScaleMinexon;

# Re-scales the shortest exon's length to unit()
#
# lg4, 28.Feb'2005

use base ('Evi::ScaleBase');

sub def_unit { # to make it overridable; in this class it is the shortest exon length
	return 5;
}

sub scale_point {
	my $self  = shift @_;
	my $point = shift @_;

	$self->rescale_if_needed();

	return  $point*$self->unit()/$self->exon_length();
}

1;
