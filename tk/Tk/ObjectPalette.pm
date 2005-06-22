package Tk::ObjectPalette;

# Generate a list of specialized object from another list of "generating" ones.
#
# lg4

use Storable;
use Tk;
use Tk::ManualOrder;
use Tk::ChoiceEditor;

use base ('Evi::DestroyReporter', 'Tk::Frame');

Construct Tk::Widget 'ObjectPalette';

sub Populate {
	my ($self,$args) = @_;

    my $activelist = delete $args->{-activelist};
    my $objectlist = delete $args->{-objectlist};

	$self->SUPER::Populate($args);

	$self->{_mo} = $self->ManualOrder(
		-labelside => 'acrosstop',
	)->pack(
		-side => 'top',
		-padx => 10,
		-pady => 10,
		-fill => 'x',
		-expand => 1,
	);

	$self->{_ce} = $self->ChoiceEditor(
		-labelside => 'acrosstop',
	)->pack(
		-side => 'left',
		-padx => 10,
		-pady => 10,
		-fill => 'x',
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
		-molabel =>    [ { -label => $self->{_mo} }, 'molabel', 'Molabel', 'The current order:' ],
		-celabel =>    [ { -label => $self->{_ce} }, 'celabel', 'Celabel', 'Please choose from here:' ],
	);
}

sub add_callback {
	my $self = shift @_;

	my $clone = Storable::dclone($self->{_ce}->getCurrobj());
	$self->{_mo}->append_object($clone);
}

1;

