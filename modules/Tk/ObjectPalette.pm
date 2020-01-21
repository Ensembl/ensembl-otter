=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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

package Tk::ObjectPalette;

# Generate a list of specialized object from another list of "generating" ones.
#
# lg4

use Storable;
use Tk;
use Tk::LabFrame;   # This class should never be inherited from,
                    # as it has bugs that break 'grid' geometry manager.
                    # Things should inherit from Tk::Frame instead, and be wrapped.
use Tk::ManualOrder;
use Tk::ChoiceEditor;

use base ('Tk::DestroyReporter', 'Tk::Frame');

Construct Tk::Widget 'ObjectPalette';

sub Populate {
	my ($self,$args) = @_;

    my $activelist = delete $args->{-activelist};
    my $objectlist = delete $args->{-objectlist};

	$self->SUPER::Populate($args);

    $self->{_mo_lf} = $self->LabFrame()->pack(
		-side => 'top',
		-padx => 10,
		-pady => 10,
		-fill => 'x',
		-expand => 1,
	);

	$self->{_mo} = $self->{_mo_lf}->ManualOrder()->pack(
		-fill => 'both',
		-expand => 1,
    );

	$self->{_ce_lf} = $self->LabFrame()->pack(
		-side => 'left',
		-padx => 10,
		-pady => 10,
		-fill => 'x',
		-expand => 1,
	);

	$self->{_ce} = $self->{_ce_lf}->ChoiceEditor()->pack(
		-fill => 'both',
		-expand => 1,
	);

	$self->Button(
		-text => 'Add',
		-command => [ \&add_callback, $self ],
	)->pack(
		-side => 'right',
		-padx => 10,
		-pady => 10,
		-fill => 'y',
		-expand => 1,
	);

	$self->ConfigSpecs(
		-activelist => [ $self->{_mo}, 'activelist', 'Activelist', $activelist?$activelist:[] ],
		-objectlist => [ $self->{_ce}, 'objectlist', 'Objectlist', $objectlist?$objectlist:[] ],
		-molabel =>    [ { -label => $self->{_mo_lf} }, 'molabel', 'Molabel', 'The current order:' ],
		-celabel =>    [ { -label => $self->{_ce_lf} }, 'celabel', 'Celabel', 'Please choose from here:' ],
	);
}

sub add_callback {
	my $self = shift @_;

	my $clone = Storable::dclone($self->{_ce}->getCurrobj());
	$self->{_mo}->append_object($clone);
}

1;

