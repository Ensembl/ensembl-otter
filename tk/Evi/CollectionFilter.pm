=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Evi::CollectionFilter;
 
# The functions of this modules are:
# (1) to keep the list of active (parametrized) sorting/filtering criteria
# (2) to keep the list of all (unparametrised) sorting/filtering criteria
# (3) to sort/filter according to the active list (using Sorter.pm)
# (4) to keep the result of sorting
# (5) to keep the "freshness" attribute (which can invalidate the previous result of sorting)
#
# lg4

use Evi::SortCriterion;	# method/params to be called on data to compute the key, direction, threshold...
use Evi::Sorter;		# performs multicriterial sorting, filtering and uniq
use Evi::Tictoc;		# the stopwatch

use base ('Tk::DestroyReporter');
 
sub new { # class method
	my $pkg			= shift @_;

	my $self = bless {}, $pkg;

    $self->name( shift @_ );
	$self->evicoll( shift @_ );
    $self->active_criteria( shift @_ || [] );
    $self->all_criteria( shift @_ || [] );

    my $uniq = shift @_;
    $self->uniq( defined($uniq) ? $uniq : 1 );

	return $self;
}

    # Gets/sets the cf's name
sub name {
    my ($self, $name) = @_;
                                                                                                                         
    if(defined($name)) {
        $self->{_name} = $name;
    }
    return $self->{_name};
}

    # Gets/sets the evidence collection
sub evicoll {
    my ($self, $evicoll) = @_;
                                                                                                                         
    if(defined($evicoll)) {
        $self->{_evicoll} = $evicoll;
    }
    return $self->{_evicoll};
}

    # Gets/sets the uniq flag.
sub uniq {
    my ($self, $uniq) = @_;

    if(defined($uniq)) {
        $self->{_uniq} = $uniq;
    }
    return $self->{_uniq};
}

    # Gets/sets the modification flag.
    # If unset, means that some data has changed and sorting/filtering has to be re-done.
sub cache_ok {
    my ($self, $newflag) = @_;

    if(defined($newflag)) {
        $self->{_cache_ok} = $newflag;
    }
    return $self->{_cache_ok};
}

    # Get/set the listref of active (parametrized) criteria.
sub active_criteria {
	my ($self, $new_list) = @_;

	if(defined($new_list)) {
		$self->{_active_criteria_lp} = $new_list;

            # invalidate the cache:
        $self->cache_ok(0);
	}
	return $self->{_active_criteria_lp};
}

    # Get/set the listref of all possible (unparametrized) criteria.
sub all_criteria {
	my ($self, $new_list) = @_;

	if(defined($new_list)) {
		$self->{_all_criteria_lp} = $new_list;

            # invalidate the cache:
        $self->cache_ok(0);
	}
	return $self->{_all_criteria_lp};
}

    # Get/set the current transcript.
    # Propagates the newly set transcript into the criteria.
sub current_transcript {
	my ($self, $transcript) = @_;

	if(defined($transcript)) {
		$self->{_current_transcript} = $transcript;

			# all_criteria are computed by EviDisplay, so we set them as well:
		for my $criterion (@{ $self->active_criteria()}, @{ $self->all_criteria()}) {
			$criterion->internalFeature('_params',[$transcript]);
		}

            # invalidate the cache:
        $self->cache_ok(0);
	}
	return $self->{_current_transcript};
}

    # Get/set the current range.
    # NB: start has to be less than end!
    # Returns a list of two elements if set and empty list if not set.
sub current_range {
	my ($self, $range_start, $range_end) = @_;

	if(defined($range_start)&&defined($range_end)) {
		$self->{_current_range} = [$range_start, $range_end];

            # invalidate the cache:
        $self->cache_ok(0);
	}
	return $self->{_current_range}
		? @{ $self->{_current_range} }
		: ();
}

    # Get the relevant chains (the ones intersecting the range OR current_transcript)
sub filter_intersecting_current_range {
	my $self = shift @_;

	my ($range_start, $range_end)
	 =	$self->current_range()
	 || ($self->current_transcript()->start(), $self->current_transcript()->end() );

	return [
		grep { $range_start<=$_->end()
		 and   $_->start()<=$range_end } @{ $self->evicoll()->get_all_matches() }
	];
}

sub results_lp {
    my $self = shift @_;

    if(!$self->cache_ok()) {
        my $tt_fs = Evi::Tictoc->new('Filtering and sorting '.$self->name() );

            $self->{_cached_results_lp}
            = $self->filter_intersecting_current_range();

                # from the matching chains with equal names take the ones with best coverage
            if($self->uniq()) {
                    $self->{_cached_results_lp} = Evi::Sorter::uniq( $self->{_cached_results_lp},
                        [ Evi::SortCriterion->new('unique by EviSeq name',
                                                'name', [],'alphabetic','ascending') ],
                        [ Evi::SortCriterion->new('optimal by EviSeq coverage',
                                                'eviseq_coverage', [], 'numeric','descending') ]
                    );
            }

            my $sorter = Evi::Sorter->new( @{ $self->active_criteria() } );

                # finally, cut off by thresholds and sort
            $self->{_cached_results_lp} = $sorter->cutsort( $self->{_cached_results_lp} );

                # flag the cached data as OK
            $self->cache_ok(1);

        $tt_fs->done();
    }

    return $self->{_cached_results_lp};
}

1;
