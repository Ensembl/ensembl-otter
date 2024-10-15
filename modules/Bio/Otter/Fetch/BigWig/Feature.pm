=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Fetch::BigWig::Feature

package Bio::Otter::Fetch::BigWig::Feature;

use strict;
use warnings;

sub new {
    my ($pkg, %args) = @_;
    my $new = \ %args;
    bless $new, $pkg;
    return $new;
}

# attributes

sub start {
    my ($self) = @_;
    my $start = $self->{'start'};
    return $start;
}

sub end {
    my ($self) = @_;
    my $end = $self->{'end'};
    return $end;
}

sub score {
    my ($self) = @_;
    my $score = $self->{'score'};
    return $score;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::BigWig::Feature

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

