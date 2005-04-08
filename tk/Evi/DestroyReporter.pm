package Evi::DestroyReporter;

# Any object that wants to report about its own destruction should inherit from this one
#
# lg4, 25.Feb'2005

sub DESTROY {
	my( $self ) = @_;
	
	my $class = ref($self);
	warn "Destroying a '$class'";
}

1;

