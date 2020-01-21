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


### Bio::Otter::GappedAlignment::Element

package Bio::Otter::GappedAlignment::Element;

use strict;
use warnings;

use Readonly;
use Bio::Otter::Utils::RequireModule qw(require_module);

use Bio::Otter::GappedAlignment::ElementTypes;

use base 'Bio::Otter::GappedAlignment::ElementI';

Readonly my %TYPE_CLASS => {
    $T_MATCH       => 'Match',
    $T_CODON       => 'Codon',
    $T_GAP         => 'Gap',
    $T_NON_EQUIV   => 'NER',
    $T_5P_SPLICE   => 'SS_5P',
    $T_3P_SPLICE   => 'SS_3P',
    $T_INTRON      => 'Intron',
    $T_SPLIT_CODON => 'SplitCodon',
    $T_FRAMESHIFT  => 'Frameshift',
};

sub _module_name {
    my ($self, $type) = @_;
    return __PACKAGE__ . '::' . $TYPE_CLASS{$type};
}

# Load all element subtype modules
#
foreach my $class (keys %TYPE_CLASS) {
    my $module = __PACKAGE__->_module_name($class);
    require_module($module);
}

sub new {
    my ($pkg, $type, $query_length, $target_length) = @_;
    $pkg->logger->logconfess("missing element type")  unless $type;
    $pkg->logger->logconfess("unknown element type")  unless $TYPE_CLASS{$type};
    $pkg->logger->logconfess("missing query_length")  unless defined $query_length;
    $pkg->logger->logconfess("missing target_length") unless defined $target_length;

    my $class = $pkg->_module_name($type);

    return $class->new($query_length, $target_length);
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::Element

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
