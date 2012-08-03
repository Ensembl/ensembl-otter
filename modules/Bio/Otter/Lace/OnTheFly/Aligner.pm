package Bio::Otter::Lace::OnTheFly::Aligner;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose;

with 'MooseX::Log::Log4perl';

use Readonly;

use Bio::Otter::GappedAlignment;
use Bio::Otter::Lace::OnTheFly::ResultSet;

Readonly our $RYO_FORMAT => 'RESULT: %S %pi %ql %tl %g %V\n';
Readonly our @RYO_ORDER => (
    '_tag',
    @Bio::Otter::GappedAlignment::SUGAR_ORDER,
    qw(
        _perc_id
        _query_length
        _target_length
        _gene_orientation
      ),
);

has type   => ( is => 'ro', isa => 'Str',                                   required => 1 );
has seqs   => ( is => 'ro', isa => 'ArrayRef[Hum::Sequence]',               required => 1 );
has target => ( is => 'ro', isa => 'Bio::Otter::Lace::OnTheFly::TargetSeq', required => 1 );

has options => ( is => 'ro', isa => 'HashRef', default => sub { {} } );
has query_type_options => ( is => 'ro', isa => 'HashRef[HashRef]',
                            default => sub { { dna => {}, protein => {} } } );

has fasta_description => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_fasta_description' );

sub _build_fasta_description {
    my $self = shift;
    return sprintf('query_%s', $self->type);
}

sub fasta_sequences {
    my $self = shift;
    return @{$self->seqs};
}

with 'Bio::Otter::Lace::OnTheFly::FastaFile';

sub is_protein {
    my $self = shift;
    return $self->type =~ /Protein/;
}

sub query_type {
    my $self = shift;
    return $self->is_protein ? 'protein' : 'dna';
}

sub run {
    my $self = shift;

    my $command = 'exonerate';

    my $query_file  = $self->fasta_file;
    my $query_type  = $self->query_type;
    my $target_file = $self->target->fasta_file;

    my %args = (
        '--targettype' => 'dna',
        '--target'     => $target_file,
        '--querytype'  => $query_type,
        '--query'      => $query_file,
        '--ryo'        => $RYO_FORMAT,
        '--showvulgar' => 'false',
        %{$self->options},
        %{$self->query_type_options->{$query_type}},
        );

    my @command_line = $self->construct_command( $command, \%args );
    $self->logger->info('Running: ', join ' ', @command_line);
    open my $raw_align, '-|', @command_line or $self->logger->logconfess("failed to run $command: $!");

    return $self->parse($raw_align);
}

sub parse {
    my ($self, $fh) = @_;

    my $result_set = Bio::Otter::Lace::OnTheFly::ResultSet->new(type => $self->type);

    while (my $line = <$fh>) {
        $result_set->add_raw_line($line);

        # We only parse our RYO lines
        next unless $line =~ /^RESULT:/;
        my @line_parts = split(' ',$line);
        my (%ryo_result, @vulgar_comps);
        (@ryo_result{@RYO_ORDER}, @vulgar_comps) = @line_parts;

        my $gapped_alignment = $self->_parse_vulgar(\%ryo_result, \@vulgar_comps);
        my $q_id = $gapped_alignment->query_id;
        $self->logger->info("RESULT found for ${q_id}");

        if ($result_set->by_query_id($q_id)) {
            $self->log->warn("Already have result for '$q_id'");
        } else {
            $result_set->add_by_query_id($q_id => $gapped_alignment);
        }
    }

    return $result_set;
}

sub _parse_vulgar {
    my ($self, $ryo_result, $vulgar_comps) = @_;

    my $vulgar_string = join(' ', @{$ryo_result}{@Bio::Otter::GappedAlignment::SUGAR_ORDER}, @$vulgar_comps);

    return Bio::Otter::GappedAlignment->from_vulgar($vulgar_string);
}

# FIXME: doesn't really belong here: more general
#
sub construct_command {
    my ($self, $command, $args) = @_;
    my @command_line = ( $command );
    foreach my $key ( keys %{$args} ) {
        if (defined (my $val = $args->{$key})) {
            push @command_line, $key, $val;
        } else {
            push @command_line, $key;
        }
    }
    return @command_line;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
