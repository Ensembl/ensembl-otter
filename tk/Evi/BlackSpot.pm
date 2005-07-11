package Evi::BlackSpot;

# break the most obvious links to other objects
# (assuming an object is a hash reference)
 
sub break_the_links {
	my $self = shift @_;

	for my $k (keys %$self) {
		delete $self->{$k};
	}
}

1;
