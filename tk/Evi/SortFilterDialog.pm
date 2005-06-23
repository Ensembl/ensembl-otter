package Evi::SortFilterDialog;
 
# A module that sorts/filters the data.
# The interactive part opens a TK window allowing to modify sorting/filtering criteria
#
# lg4

use Tk;

use Tk::ObjectPalette;     # frame that selects the sorting order

use Evi::SortCriterion;	# method/params to be called on data to compute the key, direction, threshold...
use Evi::Sorter;		# performs multicriterial sorting, filtering and uniq
use Evi::Tictoc;		# the stopwatch

use base ('Evi::DestroyReporter');
 
sub new { # class method
	my $pkg			= shift @_;

	my $self = bless {}, $pkg;

	$self->{_topwindow}	= shift @_;
	$self->{_title}		= shift @_;

	$self->{_evicoll}	= shift @_;

	$self->{_uniq}		= shift @_;

	$self->{_callback_obj} = shift @_;
	$self->{_callback_mth} = shift @_;

	$self->init_criteria(); # NB: don't forget to set current_transcript() !

	return $self;
}

# ---------------------------- TK interface part: ----------------------------

sub open {
	my $self = shift @_;

	if($self->{_window}) { # do not open two sorting windows
		$self->{_window}->raise();
	} else {

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

		$self->{_ome} = $self->{_uframe}->Optionmenu(
			-options => [ ['Show unique matches' => 1], ['Show all matches' => 0] ],
			-variable => \$self->{_uniq},
		)->pack(
			-padx => 10,
			-pady => 10,
		);

		$self->{_opa} = $self->{_window}->ObjectPalette(
			-molabel => 'Current sorting/filtering order:',
			-activelist => $self->active_criteria(),
			-celabel => 'Add more criteria:',
			-objectlist => $self->all_criteria(),
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
		$result = $self->filter_and_sort(1);
	}
	warn "closing the sorter window";
	$self->{_ome}->configure(-variable, []);
	$self->{_opa}->configure(-activelist => [], -objectlist => []);
	$self->{_opa}->destroy();
	$self->{_window}->destroy();
	delete $self->{_window};
}

sub release { # the Black Spot
	my $self = shift @_;

	for my $k (keys %$self) {
		delete $self->{$k};
	}
}

# ------------------------- Sorting/Filtering part: -------------------------------------

sub current_range {
	my ($self, $range_start, $range_end) = @_;

	if(defined($range_start)&&defined($range_end)) {
		$self->{_current_range} = [$range_start, $range_end];
	}
	return $self->{_current_range}
		? @{ $self->{_current_range} }
		: ();
}

sub active_criteria {
	my ($self, $new_list) = @_;

	if(defined($new_list)) {
		$self->{_active_criteria_lp} = $new_list;
	}
	return $self->{_active_criteria_lp};
}

sub all_criteria {
	my ($self, $new_list) = @_;

	if(defined($new_list)) {
		$self->{_all_criteria_lp} = $new_list;
	}
	return $self->{_all_criteria_lp};
}

sub current_transcript {
	my ($self, $transcript) = @_;

	if(defined($transcript)) {
		$self->{_current_transcript} = $transcript;

			# all_criteria are computed by EviDisplay, so we set them as well:
		for my $criterion (@{ $self->active_criteria()}, @{ $self->all_criteria()}) {
			$criterion->internalFeature('_params',[$transcript]);
		}
	}
	return $self->{_current_transcript};
}

sub init_criteria { # NB: current_transcript must be set after calling this function!
	my $self = shift @_;

	$self->active_criteria([
		Evi::SortCriterion->new('Analysis','analysis',
					[],'alphabetic','ascending'),
		Evi::SortCriterion->new('Taxon','taxon_name',
					[],'alphabetic','ascending'),
		Evi::SortCriterion->new('Evidence name','name',
					[],'alphabetic','ascending'),
    ]);

    $self->all_criteria([

			# include them as well:
		@{$self->active_criteria()},

			# current transcript-dependent criteria:
		Evi::SortCriterion->new('Supported introns', 'trans_supported_introns',
					[], 'numeric','descending',1),
		Evi::SortCriterion->new('Supported junctions', 'trans_supported_junctions',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Supported % of transcript','transcript_coverage',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Dangling ends (bases)','contrasupported_length',
					[], 'numeric','ascending',10),

			# transcript-independent criteria:
		Evi::SortCriterion->new('Evidence sequence coverage (%)','eviseq_coverage',
					[], 'numeric','descending',50),
		Evi::SortCriterion->new('Minimum % of identity','min_percent_id',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Start of match (slice coords)','start',
					[], 'numeric','ascending'),
		Evi::SortCriterion->new('End of match (slice coords)','end',
					[], 'numeric','descending'),
		Evi::SortCriterion->new('Source database','db_name',
					[], 'alphabetic','ascending'),
    ]);
}

sub filter_intersecting_current_range {
	my $self = shift @_;

	my ($range_start, $range_end)
	 =	$self->current_range()
	 || ($self->current_transcript()->start(), $self->current_transcript()->end() );

	return [
		grep { $range_start<=$_->end()
		 and   $_->start()<=$range_end } @{ $self->{_evicoll}->get_all_matches() }
	];
}

sub filter_and_sort {
	my ($self, $notify) = @_;

my $tt_fs = Evi::Tictoc->new("Filtering and sorting");

	my $left_matches_lp = $self->filter_intersecting_current_range();

		# from the matching chains with equal names take the ones with best coverage
	if($self->{_uniq}) {
			$left_matches_lp = Evi::Sorter::uniq($left_matches_lp,
				[ Evi::SortCriterion->new('unique by EviSeq name',
										'name', [],'alphabetic','ascending') ],
				[ Evi::SortCriterion->new('optimal by EviSeq coverage',
										'eviseq_coverage', [], 'numeric','descending') ]
			);
	}

    my $sorter = Evi::Sorter->new( @{ $self->active_criteria() } );

		# finally, cut off by thresholds and sort
	$left_matches_lp = $sorter->cutsort($left_matches_lp);

$tt_fs->done();

	if($notify) { # notify the caller:
		my $method = $self->{_callback_mth};
		$self->{_callback_obj}->$method($left_matches_lp);
	} else {
		return $left_matches_lp;
	}
}

1;
