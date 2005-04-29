package Evi::Tictoc;

# a simple stopwatch a la Matlab's tic/toc
#
# lg4

use strict;

sub new {
	my $pkg		= shift @_;
	my $title	= shift @_;
	my $start	= time;

	my $self = bless {
		'_title' => $title,
		'_start' => $start,
	}, $pkg;

	print STDERR $title." started...\n";

	return $self;
}

sub done {
	my $self = shift @_;

	$self->{_end} = time;

	print STDERR ''.$self->{_title}." done in ".($self->{_end}-$self->{_start})." sec\n";
}

1;
