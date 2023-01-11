=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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
