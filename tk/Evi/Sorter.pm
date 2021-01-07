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

package Evi::Sorter;

# 1) sorts lists of objects using a cascade of criteria (array of SortCriterion objects)
# 2) cuts them off starting from a given threshold
# 3) uniq'ues the lists given a certain field to be unique
#
# lg4, 4.Mar'2005

use Evi::SortCriterion;

sub new {
        my $pkg = shift @_;

		# include all elements that were passed to the constructor
		# Note: $self is actually an array reference
	my $self = bless [ @_ ], $pkg;

        return $self;
}

sub make {
        my $pkg  = shift @_;
	my $self = shift @_;

		# This is a "half-constructor" that blesses a given reference
		# Note: $self is actually an array reference
	bless $self, $pkg;

        return $self;
}

sub add_criteria {
	my $self = shift @_;

	push @$self, @_;

	return $self;	# to make it chainable
}

sub get_criteria { # let's pretend we may have a more complex implementation
	my $self = shift @_;

	return $self;
}

sub cut {
	my ($self,$data_lp) = @_;

	return [ grep {
		my $result = 1;
		for (my $i = 0; $result and $i < @$self; $i++) {

			my $method = $$self[$i]->{_method};
			my $params = $$self[$i]->{_params};
			my $type   = $$self[$i]->{_type};
			my $dir    = $$self[$i]->{_direction};
			my $thr    = $$self[$i]->{_threshold}; # NB: $value==$thr is INCLUDED (not cut off)

			if(defined($thr)) {
				if($type && ($thr=~/^[\+\-\d\.e]+$/) ) { # numerical cutoff
					$result &&= $dir
						? (($_->$method(@$params) <=> $thr)*$dir >= 0)
						: ($_->$method(@$params) == $thr); # equality filter
				} elsif((!$type) && length($thr)) { # alphabetical cutoff
					$result &&= $dir
						? (($_->$method(@$params) cmp $thr)*$dir >= 0)
						: ($_->$method(@$params) =~ /$thr/); # equality/match filter
				}
			}
		}
		$result;
	} @$data_lp ];
}

sub sort {
	my $self       = shift @_;
	my $data_lp    = shift @_;

	return [ sort {
		my $result = 0;
		for (my $i = 0; !$result and $i < @$self; $i++) {

			my $method = $$self[$i]->{_method};
			my $params = $$self[$i]->{_params};

			my $type   = $$self[$i]->{_type};
			my $dir    = $$self[$i]->{_direction};

			if($dir) { # if not equality filter
				$result ||= $type
					? ($b->$method(@$params) <=> $a->$method(@$params))*$dir
					: ($b->$method(@$params) cmp $a->$method(@$params))*$dir;
			}
		}
		$result;
	} @$data_lp ];
}

sub cutsort {
	my ($self,$data_lp) = @_;

	return $self->sort($self->cut($data_lp));
}

sub sort_ind { # sorts and returns indices, not the objects themselves
	my $self       = shift @_;
	my $data_lp    = shift @_;
	my $indices_of_interest_lp = shift @_ || [0..@$data_lp-1];

	return [ sort {
		my $result = 0;
		for (my $i = 0; !$result and $i < @$self; $i++) {

			my $method = $$self[$i]->{_method};
			my $params = $$self[$i]->{_params};

			my $type   = $$self[$i]->{_type};
			my $dir    = $$self[$i]->{_direction};

			$result ||= $type
				? (($data_lp->[$b])->$method(@$params) <=> ($data_lp->[$a])->$method(@$params))*$dir
				: (($data_lp->[$b])->$method(@$params) cmp ($data_lp->[$a])->$method(@$params))*$dir;
		}
		$result;
	} @$indices_of_interest_lp ];
}

sub uniq { # not a method
	my $data_lp          = shift @_;
	my $uniq_criteria_lp = shift @_;
	my $opti_criteria_lp = shift @_ || [] ; # or just take the first in the current sorting order

	my %factor_set = (); # set_with_equal_uniq_criteria --> array_of_indices
	for my $ind (0..@$data_lp-1) {
		my $factor_key = join(':', map {
									my $obj = $data_lp->[$ind];
									my $method = $_->{_method};
									my $params = $_->{_params};
									$obj->$method($params); }
							@$uniq_criteria_lp);
		push @{$factor_set{$factor_key}}, $ind;
	}

	my @uniq_indices = ();
	my $opti_sorter = Evi::Sorter->new(@$opti_criteria_lp); # common for all factor-sets

		# choose the index of the optimal element from each factor-set
	for my $factor_key (keys %factor_set) {
		push @uniq_indices, ($opti_sorter->sort_ind($data_lp,$factor_set{$factor_key}))->[0];
	}

		# sort these indices and output the data
	return [ @$data_lp[sort {$a <=> $b} @uniq_indices] ];
}

1;

