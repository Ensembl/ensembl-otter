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

package Tk::WrappedOSF;

# A wrapper that catches the basic operations of items between/within the two Listbox'es
# using inheritance and performs the same operations with the "real" data items.
#
# lg4

use Tk;

use base ('Tk::DestroyReporter','Tk::OrderedSelectionFrame');

Construct Tk::Widget 'WrappedOSF';

sub ClassInit {
	my ($class,$mw) = @_;
	$class->SUPER::ClassInit($mw);
}

sub Populate {
	my ($self,$args) = @_;

	$self->SUPER::Populate($args);

	$self->{_editor} = $self->Frame()
			->pack(-side => 'bottom');

	$self->{_active_lb}->bind('<ButtonRelease-1>' => sub{ $self->editor(); });
	$self->{_remaining_lb}->bind('<ButtonRelease-1>' => sub{ $self->kill_editor(); });

	$self->link_data([],[]);
}

sub _transfer { # NB: not an instance method, NB2: different from SUPER::_transfer
        my ($from_ref,$to_ref,@selected) = @_;

        push @$to_ref, @$from_ref[@selected];

	for my $to_del (reverse sort @selected) {
		splice @$from_ref,$to_del,1;
	}
}

sub activate_entries {
	my ($self,@selected) = @_;

		# move the selected entries to the end of the "active" list
	$self->SUPER::activate_entries(@selected);

		# perform the same on the real data:
	_transfer($self->{_remaining},$self->{_active},@selected);

	$self->editor();
}

sub deactivate_entries {
	my ($self,@selected) = @_;

		# move the selected entries to the end of the "remaining" list
	$self->SUPER::deactivate_entries(@selected);

		# perform the same on the real data:
	_transfer($self->{_active},$self->{_remaining},@selected);

	$self->kill_editor();
}

sub updown_active {
	my ($self,$high_index,$sel_index) = @_;

		# swap two elements in the interface:
	$self->SUPER::updown_active($high_index, $sel_index);

		# perform the same on the real data:
	my $low_index = $high_index-1;
	($self->{_active}->[$low_index], $self->{_active}->[$high_index]) =
		($self->{_active}->[$high_index], $self->{_active}->[$low_index]);

	$self->editor();
}

sub kill_editor {
	my $self = shift @_;

	if($self->{_eframe}) {
		$self->{_eframe}->destroy();
		$self->{_eframe} = undef;
	}
}

sub editor {
	my $self = shift @_;

	my ($ind)  = $self->{_active_lb}->curselection();
	my $obj = $self->{_active}->[$ind];

	$self->kill_editor();
	$self->{_eframe} = $self->{_editor}->Frame()->pack();

	# Show the object's private name in the editor() ?
	# if(defined(my $name = $obj->{_name})) {
	#	$self->{_eframe}->Label('-text' => "[$name]" )
	#		->pack(-side => 'left');
	# }

	for my $field ($obj->getChangeables()) {
		my $subframe = $self->{_eframe}->Frame()
			->pack(-side => 'left');

		$subframe->Label('-text' => $obj->mapName($field).':')
			->pack(-side => 'left');

		my $name2val_ref = $obj->getValueMapping()->{$field};

		if(defined($name2val_ref)) { # described by getValueMapping() => generate a RadioButtonSet

			## implementation using a set of Radiobuttons.
			## The internal<->external feature mapping is naturally used:
			#
			# for my $option (keys %$name2val_ref) {
			#	$subframe->Radiobutton(
			#		'-text' => $option,
			#		'-value'=> $name2val_ref->{$option},
			#		'-variable' => \$obj->{$field},
			#		'-command' => sub{$self->change_active_entry($ind,$obj)}
			#	)->pack(-side => 'top');
			# }


			## implementation using Tk::Optionmenu.
			## The widget does not know that internal<->external mapping mechanism exists:
			#

			my $tvar = $obj->externalFeature($field); # closure
			my $om = $subframe->Optionmenu(
				-options  => [ keys %$name2val_ref ],
				-textvariable => \$tvar,
				-command => sub {
								$obj->externalFeature($field,$tvar);
								$self->change_active_entry($ind,$obj);
							},
			)->pack(-side => 'top');

		} else { # other fields => generate a TextEntry:
			my $entry = $subframe->Entry(
					'-textvariable' => \$obj->{$field}
				    )->pack(-side => 'top');
			$entry->bind('<KeyRelease>', sub{$self->change_active_entry($ind,$obj)});
		}
	}
}

sub change_active_entry { # usually it's the same object with the same reference,
			  # but it has changed and needs to be re-prettyprinted in ListBox
	my ($self,$ind,$entry) = @_;

	$self->{_active}->[$ind] = $entry;
	$self->SUPER::change_active_entry($ind,$entry->toString());
}

sub set_active_entries { # a reference is passed inside
	my $self = shift @_;

	$self->{_active} = shift @_;
	$self->SUPER::set_active_entries(map { $_->toString() } @{$self->{_active}} );
}

sub set_remaining_entries { # a reference is passed inside
	my $self = shift @_;

	$self->{_remaining} = shift @_;
	$self->SUPER::set_remaining_entries(map { $_->toString() } @{$self->{_remaining}} );
}

sub link_data { # a hub to init both lists
	my ($self, $active, $remaining) = @_;

	$self->set_active_entries($active);
	$self->set_remaining_entries($remaining);
}

1;

