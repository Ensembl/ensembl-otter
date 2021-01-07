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

package Evi::ScaleMinexon;

# Re-scales the shortest exon's length to unit()
#
# lg4, 28.Feb'2005

use base ('Evi::ScaleBase');

sub def_unit { # to make it overridable; in this class it is the shortest exon length
	return 5;
}

sub scale_point {
	my $self  = shift @_;
	my $point = shift @_;

	$self->rescale_if_needed();

	return  $point*$self->unit()/$self->exon_length();
}

1;
