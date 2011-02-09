package Tk::DestroyReporter;

# Any class that wants to report about destruction of its instances
# should inherit from this one
#
# lg4

sub report_destruction {
	my $self = shift @_;
	
	my $class = ref($self);
	warn "Destroying a '$class'";
}

sub DESTROY {
	my $self = shift @_;

	$self->report_destruction();
}

1;

