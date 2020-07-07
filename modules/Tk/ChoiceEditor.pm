=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Tk::ChoiceEditor;

# Given a list of Mappable objects choose one and enable the user to edit its fields.
#
# lg4

use Tk;

    # Tk::LabFrame should never be inherited from,
    # as it has bugs that break 'grid' geometry manager.
    # Things should inherit from Tk::Frame instead, and be wrapped.
use base ('Tk::DestroyReporter', 'Tk::Frame');

Construct Tk::Widget 'ChoiceEditor';

sub Populate {
	my ($self,$args) = @_;

    my $objectlist = delete $args->{-objectlist};

	$self->SUPER::Populate($args);

	$self->{_selector} = $self->Optionmenu(
		-command => [\&editor_idx, $self],
	)->pack(
		-side => 'left',
		-padx => 10,
		-pady => 10,
		-fill => 'y',
		-expand => 1,
	);

	$self->ConfigSpecs(
		-objectlist => [ 'METHOD', 'objectlist', 'Objectlist', $objectlist ? $objectlist : [] ],
	);
}

sub objectlist { # the METHOD's name should match the option name minus dash
	my ($self, $new_lp) = @_;

	if(defined($new_lp)) {
		$self->{_objectlist} = $new_lp;

		$self->{_selector}->configure(-options =>
			[ map { [ $new_lp->[$_]->{_name} => $_ ]; } (0..@$new_lp-1) ]
		);
	}
	return $self->{_objectlist};
}

    # The purpose of this callback is to create a closure for $$tvar_ref,
    # which would be otherwise computed straight away.
sub tvar2obj_callback { # (not an object method)
    my ($tvar_ref, $obj, $field) = @_;
    
    $obj->externalFeature($field, $$tvar_ref );
}

sub editor_idx {
	my ($self, $idx) = @_;

	$self->{_currobj} = $self->{_objectlist}[$idx];

	if($self->{_eframe}) {
		$self->{_eframe}->destroy();
		$self->{_eframe} = undef;
	}

	$self->{_eframe} = $self->Frame()->pack();

	for my $field ($self->{_currobj}->getChangeables()) {
		my $subframe = $self->{_eframe}->Frame()
			->pack(
				-side => 'left',
				-padx => 10,
				-pady => 10,
			);

		$subframe->Label(
				'-text' => $self->{_currobj}->mapName($field).':'
			)->pack(
				-side => 'top',
				-pady => 5,
			);

		my $name2val_ref = $self->{_currobj}->getValueMapping()->{$field};

		if(defined($name2val_ref)) { # described by getValueMapping() => generate an Optionmenu

                # a closure is needed to protect it from precomputation!
			my $tvar = $self->{_currobj}->externalFeature($field);

			my $om = $subframe->Optionmenu(
				-options  => [ keys %$name2val_ref ],
				-textvariable => \$tvar,
				# -command => sub{ $self->{_currobj}->externalFeature($field, $tvar); }, # another way to make a closure
				-command => [ \&tvar2obj_callback, ( \$tvar, $self->{_currobj}, $field) ],
                                
			)->pack(
				-side => 'bottom',
				-pady => 5,
			);

		} else { # other fields => generate a TextEntry:
			my $entry = $subframe->Entry(
					'-textvariable' => \$self->{_currobj}{$field}
			)->pack(
				-side => 'bottom',
				-pady => 5,
			);
		}
	}
}

sub getCurrobj { # returns the only reference to the object (called by ObjectPalette)
	my $self = shift @_;

	return $self->{_currobj};
}

1;

