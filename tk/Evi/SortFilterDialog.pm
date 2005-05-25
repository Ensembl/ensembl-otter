package Evi::SortFilterDialog;
 
# A window allowing to modify sorting/filtering criteria
#
# lg4

use Tk::WrappedOSF;       # frame that selects the sorting order

use base ('Evi::DestroyReporter');
 
sub new { # class method
	my $pkg			= shift @_;

	my $self = bless {}, $pkg;

	$self->{_topwindow}	= shift @_;
	$self->{_title}		= shift @_;
	$self->{_active}	= shift @_;
	$self->{_remaining} = shift @_;

	$self->{_callback_obj} = shift @_;
	$self->{_callback_mth} = shift @_;

	return $self;
}

sub open {
	my $self = shift @_;

	if($self->{_window}) { # do not open two sorting windows
		$self->{_window}->raise();
	} else {

		$self->{_window} = $self->{_topwindow}->Toplevel(-title => $self->{_title});
		$self->{_window}->minsize(700,150);

		$self->{_window}->Label('-text' => 'Please select the sorting order:')
			->pack('-side' => 'top');
		my $wosf = $self->{_window}->WrappedOSF()
			->pack('-fill' => 'both', '-expand' => 1);

		$wosf->link_data( $self->{_active}, $self->{_remaining} );

		$self->{_window}->Button(
						'-text' => 'Sort & Filter',
						'-command' => [ $self => 'exit_callback', 1 ],
		)->pack('-side' => 'left');
		$self->{_window}->Button(
						'-text' => 'Cancel',
						'-command' => [ $self => 'exit_callback', 0 ],
		)->pack('-side' => 'right');

		$self->{_window}->protocol('WM_DELETE_WINDOW', [ $self => 'exit_callback', 0 ]); # ==[Cancel]
	}
}

sub exit_callback {
	my $self		= shift @_;
	my $function	= shift @_;

	if($function) {
		warn "performing the sort operation";
		my $method = $self->{_callback_mth};
		$self->{_callback_obj}->$method();
	}
	warn "closing the sorter window";
	$self->{_window}->destroy();
	delete $self->{_window};
}

sub release { # the Black Spot
	my $self = shift @_;

	for my $k (keys %$self) {
		delete $self->{$k};
	}
}

1;
