package Bio::Otter::Lace::OnTheFly::Aligner;

use namespace::autoclean;
use Moose;

use Readonly;

Readonly our $RYO_FORMAT => 'RESULT: %S %pi %ql %tl %g %V\n';
Readonly our @RYO_ORDER => qw(
    tag
    q_id
    q_start
    q_end
    q_strand
    t_id
    t_start
    t_end
    t_strand
    score
    perc_id
    q_length
    t_length
    gene_orientation
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
    open my $raw_align, '-|', @command_line or confess "failed to run $command: $!";

    return $self->parse($raw_align);
}

sub parse {
    my ($self, $fh) = @_;

    my $raw;
    my %by_query_id;

    while (my $line = <$fh>) {
	$raw .= $line;

	# We only parse our RYO lines
	next unless $line =~ /^RESULT:/;
	my @line_parts = split(' ',$line);
	my (%ryo_result, @vulgar_comps);
	(@ryo_result{@RYO_ORDER}, @vulgar_comps) = @line_parts;
	$ryo_result{vulgar_comps} = \@vulgar_comps;
	my $q_id = $ryo_result{q_id};
	print "RESULT found for ${q_id}\n";

	if ($by_query_id{$q_id}) {
	    warn "Already have result for '$q_id'";
	} else {
	    $by_query_id{$q_id} = \%ryo_result;
	}
    }

    return {
	raw         => $raw,
	by_query_id => \%by_query_id,
    };
}

# FIXME: doesn't really belong here: more general
#
sub construct_command {
    my ( $self, $command, $args ) = @_;
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
