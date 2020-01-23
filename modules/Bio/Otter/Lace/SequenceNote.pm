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


### Bio::Otter::Lace::SequenceNote

package Bio::Otter::Lace::SequenceNote;

use strict;
use warnings;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub text {
    my ($self, $text) = @_;

    if ($text) {
        $self->{'_text'} = $text;
    }
    return $self->{'_text'};
}

sub timestamp {
    my ($self, $timestamp) = @_;

    if (defined $timestamp) {
        $self->{'_timestamp'} = $timestamp;
    }
    return $self->{'_timestamp'};
}

sub is_current {
    my ($self, $is_current) = @_;

    if (defined $is_current) {
        $self->{'_is_current'} = $is_current;
    }
    return $self->{'_is_current'};
}

sub author {
    my ($self, $author) = @_;

    if ($author) {
        $self->{'_author'} = $author;
    }
    return $self->{'_author'};
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::SequenceNote

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

