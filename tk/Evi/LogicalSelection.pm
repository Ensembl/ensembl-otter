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
		'entry'		=> $entry,
		'visible'	=> 0,	# invisible by default
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

sub select {
	my ($self, $name) = @_;

	if(not $self->is_selected($name)) {
		$self->_addentry($name);
	}
}

sub deselect {
	my ($self, $name) = @_;

	delete $self->{_data}{$name};
}

sub get_list {
	my $self = shift @_;

	return [ keys %{ $self->{_data}} ];
}

sub is_visible {
	my ($self, $name) = @_;

	return $self->is_selected($name) && $self->{_data}{$name}{visible};
}

sub set_visibility {
	my ($self, $name, $visibility) = @_;

	if($self->is_selected($name)) {
		$self->{_data}{$name}{visible} = $visibility || 0;
	} else {
		warn "cannot make visible/invisible something that is not selected";
	}
}

sub any_changes_in_selection {
	my $self = shift @_;

	my $old_selection = join(',', sort map { strip_colonprefix($_->name()); }
									@{ $self->{_transcript}->transcript_info()->get_all_Evidence() });

	my $curr_selection = join(',', sort @{$self->get_list()} );

	return $old_selection ne $curr_selection;
}

sub save_to_transcript {
	my $self = shift @_;

	if( $self->any_changes_in_selection() ) {
		$self->{_transcript}->transcript_info()->flush_Evidence();

		# for my $eviname (keys %{$self->{_data}}) {
		#	print "\t".$self->{_data}{$eviname}{entry}->name();
		#	print "\t".$self->{_data}{$eviname}{visible}."\n";
		# }
        
		$self->{_transcript}->transcript_info()->add_Evidence(
			map { $self->{_data}{$_}{entry}; }
					(keys %{ $self->{_data}})
		);

        # use Data::Dumper;
        # print STDERR Dumper($self->{_transcript}->transcript_info);

		return 1;
	} else { # nothing to be done
		return 0;
	}
}

1;

