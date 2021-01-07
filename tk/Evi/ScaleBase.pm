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

package Evi::ScaleBase;

# A base class for the scalers that are used to draw transcripts/evichains.
# Re-scales everything by unit()
#
# lg4, 28.Feb'2005

sub def_unit { # to make it overridable; in this class it is the simple scale
	return 1;
}

sub new {
	my $pkg = shift @_;
	my $self = bless { }, $pkg;

	$self->unit( @_ ? shift @_ : $self->def_unit());

	return $self;
}

sub unit {
	my $self = shift @_;

	if(@_) {
		$self->{_unit} = shift @_;
	}
	return $self->{_unit};
}

sub needs_rescaling { # remembers and returns the state (0|1)
	my $self = shift @_;

	if(@_) {
		$self->{_needs} = shift @_;
	}
	return $self->{_needs};
}

sub get_sorted_points_lp {
	my $self = shift @_;

	my $sorted_lp = [ sort {$a <=> $b} (keys %{$self->{_multiset}}) ];
	$self->{_min} = $sorted_lp->[0];
	$self->{_max} = $sorted_lp->[@$sorted_lp-1];

	return $sorted_lp;
}

sub rescale_if_needed {
	my $self  = shift @_;

	if($self->needs_rescaling()) {
		$self->get_sorted_points_lp(); # to compute min/max
		$self->needs_rescaling(0);
	}
}

sub exon_length {
	my ($self,$newlen) = @_;

	if(  $newlen
	and (  (!$self->{_min_exon_length})
		or ($newlen < $self->{_min_exon_length})
		)
	) {
		$self->{_min_exon_length} = $newlen;
	}
	return $self->{_min_exon_length};
}

sub add_pair {
	my ($self, $start, $end)  = @_;

	$self->add_point($start);
	$self->add_point($end);

	$self->exon_length($end-$start);
}

sub add_point {
	my $self  = shift @_;
	my $coord = shift @_;

	$self->{_multiset}{$coord}++;

	$self->needs_rescaling(1);
}

sub delete_point { # reserved for future use
	my $self  = shift @_;
	my $coord = shift @_;

	$self->{_multiset}{$coord}--;

	$self->needs_rescaling(1);
}

sub get_unscaled_min {
	my $self  = shift @_;

	$self->rescale_if_needed();

	return $self->{_min};
}

sub get_unscaled_max {
	my $self  = shift @_;

	$self->rescale_if_needed();

	return $self->{_max};
}

sub get_scaled_min {
	my $self  = shift @_;
	return $self->scale_point($self->get_unscaled_min());
}

sub get_scaled_max {
	my $self  = shift @_;
	return $self->scale_point($self->get_unscaled_max());
}

sub scale_point {
	my $self  = shift @_;
	my $point = shift @_;

	$self->rescale_if_needed();

	return  $self->unit()*$point;
}

1;
