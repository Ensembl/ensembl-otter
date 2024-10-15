=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Evi::LogicalSelection;

# Manage the logical selection (Bio::Otter::Evidence + visibility bit)
#
# lg4

sub strip_colonprefix { # not a method
	my $name = shift @_;

	return ($name=~/:(.*)$/)
			? $1
			: $name;
}

sub _addentry {
	my ($self, $name, $entry) = @_;

	if(not $entry) { # then make it
		my $representative_chain = $self->{_evicoll}->get_all_matches_by_name($name)->[0];
		
		$entry = Bio::Otter::Evidence->new(
					-NAME => $representative_chain->prefixed_name(),
					-TYPE => $representative_chain->evitype(),
		);
	}

	$self->{_data}{$name} = {
		'_entry'	=> $entry,
		'_visible'	=> {},	# invisible by default
	};
}

sub new {
	my ($pkg, $evicoll, $transcript) = @_;

	my $self = bless {
		'_evicoll'		=> $evicoll,
		'_transcript'	=> $transcript,
		'_data'			=> {},
	}, $pkg;

	if($transcript) {
		for my $evientry (@{ $transcript->transcript_info()->get_all_Evidence() }) {
			my $name = strip_colonprefix($evientry->name());

			$self->_addentry($name, $evientry);
		}
	}

	return $self;
}

sub is_selected {
	my ($self, $name) = @_;

	return exists($self->{_data}{$name});
}

sub select_byname {
	my ($self, $name) = @_;

	if(not $self->is_selected($name)) {
		$self->_addentry($name);
	}
    $self->{_data}{$name}{_visible} = {}; # force invisibility by default
}

sub deselect_byname {
	my ($self, $name) = @_;

	delete $self->{_data}{$name};
}

sub get_namelist {
	my $self = shift @_;

	return [ keys %{ $self->{_data}} ];
}

sub get_visible_indices_by_name {
	my ($self, $name) = @_;

	if($self->is_selected($name)) {
        return [keys %{$self->{_data}{$name}{_visible}}];
    } else {
        return [];
    }
}

sub get_all_visible_indices {
	my $self = shift @_;

    my @indices = ();

    for my $name (@{$self->get_namelist()}) {
        push @indices, @{$self->get_visible_indices_by_name($name)};
    }
    return \@indices;
}

sub is_visible {
	my ($self, $name) = @_;

    return scalar(@{$self->get_visible_indices_by_name($name)});
}

sub set_visibility {
	my ($self, $name, $visibility, $screendex) = @_;

	if($self->is_selected($name)) {
        if($visibility) {
            $self->{_data}{$name}{_visible}{$screendex} = 1;
        } elsif(exists($self->{_data}{$name}{_visible}{$screendex})) {
            delete $self->{_data}{$name}{_visible}{$screendex};
        }
	} else {
		warn "cannot make visible/invisible something that is not selected";
	}
}

sub any_changes_in_selection {
	my $self = shift @_;

	my $old_selection = join(',', sort map { strip_colonprefix($_->name()); }
									@{ $self->{_transcript}->transcript_info()->get_all_Evidence() });

	my $curr_selection = join(',', sort @{$self->get_namelist()} );

	return $old_selection ne $curr_selection;
}

sub save_to_transcript { # no check here, just force it
	my $self = shift @_;

	$self->{_transcript}->transcript_info()->flush_Evidence();

	$self->{_transcript}->transcript_info()->add_Evidence(
		map { $self->{_data}{$_}{_entry}; }
				(keys %{ $self->{_data}})
	);
}

1;

