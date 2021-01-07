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


### Bio::Vega::HitDescription

package Bio::Vega::HitDescription;

use strict;
use warnings;

use warnings;

use Bio::EnsEMBL::Utils::Argument  qw( rearrange );

sub new {
    my ($caller, @args) = @_;

    my ($hit_name, $hit_length, $hit_sequence_string,
        $description, $taxon_id, $db_name) = rearrange(
      [ 'HIT_NAME', 'HIT_LENGTH', 'HIT_SEQUENCE_STRING',
        'DESCRIPTION', 'TAXON_ID', 'DB_NAME' ],
        @args);
    my $class = ref($caller) || $caller;
    return bless {
        _hit_name            => $hit_name,
        _hit_length          => $hit_length,
        _hit_sequence_string => $hit_sequence_string,
        _description         => $description,
        _taxon_id            => $taxon_id,
        _db_name             => $db_name,
    }, $class;
}

sub hit_name {
    my ($self, $hit_name) = @_;

    if ($hit_name) {
        $self->{'_hit_name'} = $hit_name;
    }
    return $self->{'_hit_name'};
}

sub hit_length {
    my ($self, $hit_length) = @_;

    if ($hit_length) {
        $self->{'_hit_length'} = $hit_length;
    }
    return $self->{'_hit_length'};
}

sub hit_sequence_string {
    my ($self, $hit_sequence_string) = @_;

    if ($hit_sequence_string) {
        $self->{'_hit_sequence_string'} = $hit_sequence_string;
    }
    return $self->{'_hit_sequence_string'};
}

sub get_and_unset_hit_sequence_string {
    my ($self) = @_;

    my $seq = $self->{'_hit_sequence_string'};
    $self->{'_hit_sequence_string'} = undef;
    return $seq;
}

sub description {
    my ($self, $description) = @_;

    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub taxon_id {
    my ($self, $taxon_id) = @_;

    if ($taxon_id) {
        $self->{'_taxon_id'} = $taxon_id;
    }
    return $self->{'_taxon_id'};
}

sub db_name {
    my ($self, $db_name) = @_;

    if ($db_name) {
        $self->{'_db_name'} = $db_name;
    }
    return $self->{'_db_name'};
}


1;

__END__

=head1 NAME - Bio::Vega::HitDescription

=head1 DESCRIPTION

The HitDescription object provides extra
information about database matches that is not
provided by the AlignFeature objects to which it
is attached.

=head1 METHODS

=over 4

=item hit_length

The length of the entire hit sequence - not just
the region matched.

=item description

A one line description of the sequence.

=item taxon_id

The numeric NCBI taxonomy database ID for the
node (which is usually species).

=item db_name

The database which the hit belongs to.

=back

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

