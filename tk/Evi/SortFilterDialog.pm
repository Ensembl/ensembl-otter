package Evi::SortFilterDialog;
 
# A module that interacts with user and modifies the list of sorting/filtering criteria.
# When it's done, it signals to the caller by activating the callback.
#
# lg4

use Evi::CollectionFilter; # the sorting/filtering criteria live here

use Tk;
use Tk::ObjectPalette;     # frame that selects the sorting order

use base ('Evi::DestroyReporter','Evi::BlackSpot');
 
sub new { # class method
	my $pkg			= shift @_;

	my $self = bless {}, $pkg;

	$self->{_topwindow}	= shift @_;
	$self->{_title}		= shift @_;

	$self->{_cf}        = shift @_;

	$self->{_callback_obj} = shift @_;
	$self->{_callback_mth} = shift @_;

	return $self;
}

sub open {
	my $self = shift @_;

	if($self->{_window}) { # do not open two sorting windows
		$self->{_window}->raise();
	} else {

            # initialize the LOCAL COPIES of the data (to be able to [Cancel])
        my $uniq_init = $self->{_cf}->uniq();
        my $uniq_variable = $uniq_init;
        my $current_activelist = [ @{ $self->{_cf}->active_criteria() } ];

		$self->{_window} = $self->{_topwindow}->Toplevel(-title => $self->{_title});
		$self->{_window}->minsize(700,150);

		$self->{_uframe} = $self->{_window}->LabFrame(
			-label => 'Uniqueness of names:',
			-labelside => 'acrosstop',
		)->pack(
			-side => 'top',
			-padx => 10,
			-pady => 10,
			-fill => 'x',
			-expand => 1,
		);

        my %uniq_textmap = (
            0 => 'Show all matches',
            1 => 'Show unique matches',
        );

            #
            # NB: -variable is not used for initialization of Optionmenu !
            # Since it is declared as "PASSIVE", it does quite the opposite instead:
            # spoils the original value even if there was originally something meaningful.
            #
            # This is why we are forced to use $uniq_variable for PASSIVE
            # and $uniq_init for initialization.
            #
		$self->{_ome} = $self->{_uframe}->Optionmenu(
			-options => [ map { [ $uniq_textmap{$_} => $_ ]; } (keys %uniq_textmap) ],
			-variable => \$uniq_variable,
		)->pack(
			-padx => 10,
			-pady => 10,
		);

            # now, set it explicitly
        $self->{_ome}->setOption($uniq_textmap{$uniq_init}, $uniq_init); # enforce it

		$self->{_opa} = $self->{_window}->ObjectPalette(
			-molabel => 'Current sorting/filtering order:',
			-activelist => $current_activelist,
			-celabel => 'Add more criteria:',
			-objectlist => $self->{_cf}->all_criteria(),
		)->pack('-fill' => 'both', '-expand' => 1);

		$self->{_window}->Button(
						'-text' => 'Sort & Filter',
						'-command' => [ $self => 'close_window_callback', 1 ],
		)->pack(
			-side => 'right',
			-padx => 10,
			-pady => 10,
		);
		$self->{_window}->Button(
						'-text' => 'Cancel',
						'-command' => [ $self => 'close_window_callback', 0 ],
		)->pack(
			-side => 'right',
			-padx => 10,
			-pady => 10,
		);

			# Killing the window is equivalent to 'Cancel':
		$self->{_window}->protocol('WM_DELETE_WINDOW', [ $self => 'close_window_callback', 0 ]);
	}
}

sub close_window_callback {
	my $self		= shift @_;
	my $function	= shift @_;

	if($function) {
            # pull the data out of the interfaces
        $self->{_cf}->uniq( ${$self->{_ome}->cget(-variable)} );
        $self->{_cf}->active_criteria( $self->{_opa}->cget(-activelist) ); # invalidates the cache automatically

		my $method = $self->{_callback_mth};
		$self->{_callback_obj}->$method();
	}
	warn "closing the sorter window";
	$self->{_ome}->configure(-variable, []);
	$self->{_opa}->configure(-activelist => [], -objectlist => []);
	$self->{_opa}->destroy();
	$self->{_window}->destroy();
	delete $self->{_window};
}

1;
