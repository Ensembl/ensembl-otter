=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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

package Evi::CF_Set;
 
# Manages the list of CollectionFilter:s
#
# lg4

use Evi::CollectionFilter;

use base ('Tk::DestroyReporter');
 
sub new { # class method
	my $pkg			= shift @_;

	my $self = bless {}, $pkg;

    if(@_) {
        $self->evicoll(shift @_);

            # either pass a list_ref, or an empty [], or it will be initialized by default
        $self->filterlist(
            @_
            ? shift @_
            : $self->default_filterlist()
        );
    }

	return $self;
}

    # Gets/sets the list of filters
sub filterlist {
    my ($self, $filterlist) = @_;

    if(defined($filterlist)) {
        $self->{_filterlist} = $filterlist;
    }
    return $self->{_filterlist} || [];
}

    # Gets/sets(+propagates) the evidence collection
sub evicoll {
    my ($self, $evicoll) = @_;

    if(defined($evicoll)) {
        $self->{_evicoll} = $evicoll;

        for my $cf (@{ $self->filterlist()}) {
            $cf->evicoll($evicoll);
        }
    }
    return $self->{_evicoll};
}

    # Gets/sets(+propagates) the current_transcript
sub current_transcript {
    my ($self, $transcript) = @_;

    if(defined($transcript)) {
        $self->{_current_transcript} = $transcript;

        for my $cf (@{ $self->filterlist()}) {
            $cf->current_transcript($transcript);
        }
    }
    return $self->{_current_transcript};
}

    # Gets/sets(+propagates) the current range
    # NB: start has to be less than end!
    # Returns a list of two elements if set and empty list if not set.
sub current_range {
	my ($self, $range_start, $range_end) = @_;

	if(defined($range_start)&&defined($range_end)) {
		$self->{_current_range} = [$range_start, $range_end];

        for my $cf (@{ $self->filterlist()}) {
            $cf->current_range( $self->{_current_range} );
        }
	}
	return $self->{_current_range}
		? @{ $self->{_current_range} }
		: ();
}

    # the default initialization of the filterlist (3 collectionfilters)
sub default_filterlist {
    my $self = shift @_;

    my $palette = [
                            # include the active ones as well
                    Evi::SortCriterion->new('Analysis','analysis',
                                            [],'alphabetic','ascending'),
                    Evi::SortCriterion->new('Taxon','taxon_name',
                                            [],'alphabetic','ascending'),
                    Evi::SortCriterion->new('Evidence name','name',
                                            [],'alphabetic','ascending'),
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
    ];


    my $vertrna = Evi::CollectionFilter->new(
                'Vertebrate mRNAs',
                $self->evicoll(),
                [
                    Evi::SortCriterion->new('Analysis','analysis',
                        [],'alphabetic','is','vertrna'),
                    Evi::SortCriterion->new('Taxon','taxon_name',
                        [],'alphabetic','ascending'),
                    Evi::SortCriterion->new('Evidence name','name',
                        [],'alphabetic','ascending'),
                ],
                $palette,
                1,
    );
    my $est2genome = Evi::CollectionFilter->new(
                'ESTs',
                $self->evicoll(),
                [
                    Evi::SortCriterion->new('Analysis','analysis',
                        [],'alphabetic','is','Est2genome'),
                    Evi::SortCriterion->new('Taxon','taxon_name',
                        [],'alphabetic','ascending'),
                    Evi::SortCriterion->new('Evidence name','name',
                        [],'alphabetic','ascending'),
                ],
                $palette,
                1,
    );
    my $proteins = Evi::CollectionFilter->new(
                'Proteins',
                $self->evicoll(),
                [
                    Evi::SortCriterion->new('Analysis','analysis',
                        [],'alphabetic','is','Uniprot'),
                    Evi::SortCriterion->new('Taxon','taxon_name',
                        [],'alphabetic','ascending'),
                    Evi::SortCriterion->new('Evidence name','name',
                        [],'alphabetic','ascending'),
                ],
                $palette,
                1,
    );

    return [$vertrna, $est2genome, $proteins];
}

sub results_lp {
    my $self = shift @_;

    my @results = ();

    for my $cf (@{ $self->filterlist()}) {
        push @results, @{ $cf->results_lp() };
    }

    return \@results;
}

1;

