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
