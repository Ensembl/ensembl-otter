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


### Bio::Otter::GappedAlignment::ElementTypes

package Bio::Otter::GappedAlignment::ElementTypes;

use strict;
use warnings;

use Readonly;

use Exporter qw(import);

# Element types
Readonly our $T_MATCH       => 'M';
Readonly our $T_CODON       => 'C';
Readonly our $T_GAP         => 'G';
Readonly our $T_NON_EQUIV   => 'N';
Readonly our $T_5P_SPLICE   => '5';
Readonly our $T_3P_SPLICE   => '3';
Readonly our $T_INTRON      => 'I';
Readonly our $T_SPLIT_CODON => 'S';
Readonly our $T_FRAMESHIFT  => 'F';

our %EXPORT_TAGS = ( types => [ qw(
    $T_MATCH
    $T_CODON
    $T_GAP
    $T_NON_EQUIV
    $T_5P_SPLICE
    $T_3P_SPLICE
    $T_INTRON
    $T_SPLIT_CODON
    $T_FRAMESHIFT
                     ) ] );

Exporter::export_tags('types');

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::ElementTypes

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
