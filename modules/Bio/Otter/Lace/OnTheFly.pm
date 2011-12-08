package Bio::Otter::Lace::OnTheFly;

use namespace::autoclean;
use Moose;

use File::Temp;

use Bio::Otter::Lace::OnTheFly::Aligner;
use Bio::Otter::Lace::OnTheFly::QueryValidator;

has 'query_validator' => (
    is      => 'ro',
    isa     => 'Bio::Otter::Lace::OnTheFly::QueryValidator',
    handles => [qw( confirmed_seqs seq_types seqs_for_type seq_by_name )],
    writer  => '_set_query_validator',
    );

has target_seq           => ( is => 'ro', isa => 'Hum::Sequence', required => 1 );

has target_fasta_file    => ( is => 'ro', isa => 'File::Temp',
                              lazy => 1, builder => '_build_target_fasta_file', init_arg => undef );

sub BUILD {
    my ( $self, $params ) = @_;

    $self->_set_query_validator(Bio::Otter::Lace::OnTheFly::QueryValidator->new($params));
    return;
}

sub aligners_for_each_type {
    my $self = shift;

    my @aligners;
    foreach my $type ( $self->seq_types ) {
        push @aligners, Bio::Otter::Lace::OnTheFly::Aligner->new(
            type         => $type,
            seqs         => $self->seqs_for_type($type),
            target_fasta => $self->target_fasta_file,
            );
    }
    return @aligners;
}

sub _build_target_fasta_file {
    my $self = shift;

    my $template = "otf_target_${$}_XXXXX";
    my $file = File::Temp->new(
        TEMPLATE => $template,
        TMPDIR   => 1,
        SUFFIX   => '.fa',
        UNLINK   => 0,         # for now
        );

    my $ts_out  = Hum::FastaFileIO->new("> $file");
    $ts_out->write_sequences( $self->target_seq );
    $ts_out = undef;            # flush

    return $file;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
