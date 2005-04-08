package Evi::MappableData;

# A virtual interface for a data class that has certain fields
# with two representations (Printable <-> Internal).
#
# lg4, 8.Dec'2004

use Carp;

sub new {       # will set whatever is passed via a hash

        my $pkg = shift @_;

        return bless { @_ }, $pkg;
}

sub getValueMapping { # this method has to be overridden
	return { };
}

sub getChangeables { # this method may be overridden
	my $self = shift @_;

	return keys %{$self->getValueMapping()};
}

sub mapName { # the simplest general approach
	my ($self,$name) = @_;

	$name=~s/\_/\ /g;
	return $name;
}

sub internalFeature {
	my $self    = shift @_;
	my $feature = shift @_;

	if(scalar(@_)) {
		$self->{$feature} = shift @_;
	}
	return $self->{$feature};
}

sub externalFeature {
	my $self    = shift @_;
	my $feature = shift @_;

	my $featuremap = $self->getValueMapping()->{$feature};

	if(defined($featuremap)) {
		if(scalar(@_)) {
			my $external = shift @_;
			if(!exists($featuremap->{$external})) {
				confess "No such $feature as '$external', "
					."please choose from ("
					.join(', ', keys %$featuremap).")";
			}
			$self->{$feature} = $featuremap->{$external};
			return $external;
		} else {
			if(!exists({reverse %$featuremap}->{$self->{$feature}})) {
				confess "$feature '".$self->{$feature}."' does not map "
					."to any valid symbol.\nPlease choose from ("
					.join(', ', values %$featuremap).")";
			}
			return {reverse %$featuremap}->{$self->{$feature}};
		}
	} else { # no mapping is needed
		if(scalar(@_)) {
			$self->{$feature} = shift @_;
		}
		return $self->{$feature};
	}
}

sub getPrintables { # you may need to override it to shorten the list
	my $self = shift @_;

	return sort keys(%$self);
}

sub toString {
	my $self = shift @_;

	my @keylist = scalar(@_) ? @_ : $self->getPrintables();

	return join(', ', map { my $ef = $self->externalFeature($_);
				$self->mapName($_)." => ".(defined($ef)?$ef:'undef'); } @keylist );
}

sub toStringInternal { # mostly for debug purposes
        my $self = shift @_;

	my @keylist = scalar(@_) ? @_ : (sort (keys %$self));

        return join(', ', map { "$_ => ".$self->{$_} } sort (keys %$self) );
}

1;

