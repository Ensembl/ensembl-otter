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


### Bio::Otter::Mapping::Equiv

package Bio::Otter::Mapping::Equiv;

# This class represents the case where the local assembly is
# equivalent to a remote one and there is no need to map.  An object
# requests features from the remote assembly and passes them to the
# target without mapping the endpoints.

use strict;
use warnings;

sub new {
    my ($pkg, @args) = @_;
    my $new = { @args };
    die "missing equivalent chr" unless $new->{-chr};
    return bless $new, $pkg;
}

sub do_features {
    my ($self, $source, $start, $end, $target) = @_;
    $target->($_, $_->start, $_->end)
        for @{$source->features($self->{-chr}, $start, $end)};
    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Mapping::Equiv

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

