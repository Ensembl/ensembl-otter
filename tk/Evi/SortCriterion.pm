package Evi::SortCriterion;

# One criterion by which to {cut|sort|cutsort}
# (contains a fieldname, a type, a direction and a threshold).
# An element of the array used by Sorter.pm
#
# lg4

use base ('Evi::MappableData');

# ->{_name}      is just the "external" name for that particular criterion/field
# ->{_method}    holds the method name to call, by which to sort
# ->{_params}    holds the reference to the array of params for the method
# ->{_type}      defines whether the sorting is to be alphabetic or numeric
# ->{_direction} defines the accendancy/descendancy of this particular criterion
# ->{_threshold} defines inclusive thresholds for every criterion

my $value_mapping = {
	'_type' => {
		'numeric'    => 1,
		'alphabetic' => 0,
		},
	'_direction' => {
		'ascending'  => -1,
		'is'         =>  0,
		'descending' =>  1,
		},
};

my $name_mapping = {
	'_type' => 'Type',
	'_direction' => 'Sorting direction',
	'_threshold' => 'Cut-off value',
};

sub getValueMapping { # the default,empty "interface" method is overridden:
	return $value_mapping;
}

sub getChangeables { # the "universal" method is overridden:
	return ('_direction','_threshold');
}

sub mapName {
	my ($self,$name) = @_;
	
	if(exists($name_mapping->{$name})) {
		return $name_mapping->{$name};
	} else {
		return $self->SUPER::mapName($name);
	}
}

sub new {
        my $pkg = shift @_;
	my ($name, $method, $params, $type, $dir, $thr) = @_;

	my $self = bless {}, $pkg;

	$self->externalFeature('_name'      => $name);

	$self->externalFeature('_method'     => $method);
	$self->externalFeature('_params'     => $params);

	$self->externalFeature('_type'      => $type);
	$self->externalFeature('_direction' => $dir);
	$self->externalFeature('_threshold' => $thr);

        return $self;
}

sub compute {
	my ($self, $obj) = @_;
	my $method = $self->{_method};

	return $obj->$method(@{$self->{_params}});
}

sub toString {
	my $self = shift @_;

	my $thr = $self->{_threshold};
	my $type = $self->{_type};
	return join('',	$self->externalFeature('_name'),
	#	   '/', $self->externalFeature('_type'),
		   ': ',$self->externalFeature('_direction'),
			(defined($thr)&&length($thr)&&((!$type) || ($thr=~/^[\d\-\+\.e]+$/)))
				?", cut-off @ $thr"
				:", no cut-off");
}

1;

