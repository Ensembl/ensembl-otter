package Evi::Tictoc;

# a simple stopwatch a la Matlab's tic/toc
#
# 4.Mar'2005, lg4

use strict;

sub new {
	my $pkg = shift @_;

	my $self = bless {}, $pkg;
	$self->{_start} = time;

	my $title = shift @_;
	print STDERR $title."... ";

	return $self;
}

sub done {
	my $self = shift @_;

	$self->{_end} = time;

	print STDERR "done in ".($self->{_end}-$self->{_start})." sec\n";
}

1;
