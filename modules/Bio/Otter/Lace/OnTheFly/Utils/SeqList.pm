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

package Bio::Otter::Lace::OnTheFly::Utils::SeqList;

use namespace::autoclean;
use Moose;

has seqs                 => ( is => 'ro', isa => 'ArrayRef[Hum::Sequence]', default => sub{ [] } );

has seqs_by_name         => ( is => 'ro', isa => 'HashRef[Hum::Sequence]',
                              lazy => 1, builder => '_build_seqs_by_name', init_arg => undef );

sub _build_seqs_by_name {       ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my %name_seq;
    for my $seq (@{$self->seqs}) {
        $name_seq{ $seq->name } = $seq;
    }

    return \%name_seq;
}

sub seq_by_name {
    my ($self, $name) = @_;
    return $self->seqs_by_name->{$name};
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
