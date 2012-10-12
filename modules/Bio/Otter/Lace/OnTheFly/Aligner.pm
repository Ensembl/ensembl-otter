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

has softmask_target => ( is => 'ro', isa => 'Bool' );

has options => ( is => 'ro', isa => 'HashRef', default => sub { {} } );
has query_type_options => ( is => 'ro', isa => 'HashRef[HashRef]',
                            default => sub { { dna => {}, protein => {} } } );

has default_options    => ( is => 'ro', isa => 'HashRef', init_arg => undef, builder => '_build_default_options' );
has default_qt_options => ( is => 'ro', isa => 'HashRef', init_arg => undef, builder => '_build_default_qt_options' );

sub _default_options    { return { '--bestn' => 1 }; };
sub _default_qt_options { return { dna => {}, protein => {} }; };

sub _build_default_options {    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $defaults       = $self->_default_options;
    my $child_defaults = inner() || { };
    my $default_options = { %{$defaults}, %{$child_defaults} };
    return $default_options;
}

sub _build_default_qt_options { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $defaults       = $self->_default_qt_options;
    my $child_defaults = inner() || { dna => {}, protein => {} };
    return { map { $_ => { %{$defaults->{$_}}, %{$child_defaults->{$_}} } } qw( dna protein ) };
}

has fasta_description => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_fasta_description' );

sub _build_fasta_description {  ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
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
        '--showsugar'  => 'false',
        '--showcigar'  => 'false',
        %{$self->default_options},
        %{$self->default_qt_options->{$query_type}},
        %{$self->options},
        %{$self->query_type_options->{$query_type}},
        '--softmasktarget' => $self->softmask_target ? 'yes' : 'no',
        );

    my @command_line = $self->construct_command( $command, \%args );
    $self->logger->info('Running: ', join ' ', @command_line);
    open my $raw_align, '-|', @command_line or $self->logger->logconfess("failed to run $command: $!");

    return $self->parse($raw_align);
}

sub parse {
    my ($self, $fh) = @_;

    my $result_set = Bio::Otter::Lace::OnTheFly::ResultSet->new(aligner => $self);

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
        }
        $result_set->add_by_query_id($q_id => $gapped_alignment);
    }

    return $result_set;
}

sub _parse_vulgar {
    my ($self, $ryo_result, $vulgar_comps) = @_;

    my $vulgar_string = join(' ', @{$ryo_result}{@Bio::Otter::GappedAlignment::SUGAR_ORDER}, @$vulgar_comps);

    my $ga = Bio::Otter::GappedAlignment->from_vulgar($vulgar_string);

    $ga->percent_id($ryo_result->{_perc_id});
    $ga->gene_orientation($ryo_result->{_gene_orientation});

    $ga = $ga->reverse_alignment if $ga->gene_orientation eq '-';

    return $ga;
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
