=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Lace::OnTheFly;

use namespace::autoclean;
use Moose::Role;

requires 'build_target_seq';
requires 'build_builder';

use Bio::Otter::Lace::OnTheFly::QueryValidator;
use Bio::Otter::Lace::OnTheFly::Runner;
use Bio::Otter::Lace::OnTheFly::TargetSeq;

with 'MooseX::Log::Log4perl';

has 'query_validator' => (
    is      => 'ro',
    isa     => 'Bio::Otter::Lace::OnTheFly::QueryValidator',
    handles => [qw( confirmed_seqs seq_types seqs_for_type seqs_by_name seq_by_name )],
    writer  => '_set_query_validator',
    );

has 'target_seq_obj'  => (
    is     => 'ro',
    isa    => 'Bio::Otter::Lace::OnTheFly::TargetSeq',
    handles => {
        target_fasta_file => 'fasta_file',
        target_start      => 'start',
        target_end        => 'end',
        target_seq        => 'target_seq',
        target_all_repeat => 'all_repeat',
        },
    writer => '_set_target_seq_obj',
    );

has 'softmask_target' => ( is => 'ro', isa => 'Bool' );
has 'clear_existing'  => ( is => 'ro', isa => 'Bool' );

has 'aligner_options' => (
    traits => [ 'Hash' ],
    is  => 'ro',
    isa => 'HashRef',
    default => sub { {} },
    handles => {
        _set_aligner_option => 'set',
    },
    );

has 'aligner_query_type_options' => (
    is  => 'ro',
    isa => 'HashRef',
    default => sub { { dna => {}, protein => {} } },
    );

has 'bestn'    => (
    is => 'ro',
    isa => 'Int',
    trigger => sub { my ($self, $val) = @_; $self->_set_aligner_option('--bestn', $val) },
);

has 'maxintron'    => (
    is => 'ro',
    isa => 'Int',
    trigger => sub { my ($self, $val) = @_; $self->_set_aligner_option('--maxintron', $val) },
);

has 'logic_names' => (
    is  => 'ro',
    isa => 'ArrayRef[Str]',
    required => 1,
);

sub BUILD {
    my ($self, $params) = @_;

    $self->_set_query_validator( Bio::Otter::Lace::OnTheFly::QueryValidator->new($params));
    $self->_set_target_seq_obj( $self->build_target_seq($params) );

    return;
}

sub pre_launch_setup {
    my ($self, %opts) = @_;

    if ($self->clear_existing) {

        my $slice = $opts{slice};
        my $vega_dba = $slice->adaptor->db;
        my $analysis_a = $vega_dba->get_AnalysisAdaptor;
        my $dna_saf_a  = $vega_dba->get_DnaSplicedAlignFeatureAdaptor;
        my $pro_saf_a  = $vega_dba->get_ProteinSplicedAlignFeatureAdaptor;

        foreach my $logic_name (@{$self->logic_names}) {
            if (my $analysis = $analysis_a->fetch_by_logic_name($logic_name)) {
                my $saf_a = $logic_name =~ /protein/i ? $pro_saf_a : $dna_saf_a;
                $saf_a->remove_by_analysis_id($analysis->dbID);
            }
        }
    }
    return;
}

sub builders_for_each_type {
    my $self = shift;

    my @builders;
    foreach my $type ( $self->seq_types ) {
        push @builders, $self->build_builder(
            type               => $type,
            query_seqs         => $self->seqs_for_type($type),
            target             => $self->target_seq_obj,
            softmask_target    => $self->softmask_target,
            options            => $self->aligner_options,
            query_type_options => $self->aligner_query_type_options,
            );
    }
    return @builders;
}

# Default runner is a plain one
#
sub build_runner {
    my ($self, @params) = @_;
    return Bio::Otter::Lace::OnTheFly::Runner->new(@params);
}

sub prep_and_store_request_for_each_type {
    my ($self, $session_window, $caller_key) = @_;

    my $ace_db = $session_window->AceDatabase;
    my $sql_db = $ace_db->DB;

    # Clear columns if requested
    $self->pre_launch_setup(slice => $sql_db->session_slice);

    my $request_adaptor = $sql_db->OTFRequestAdaptor;

    my @method_names;

    foreach my $builder ( $self->builders_for_each_type ) {

        $self->logger->info("Running exonerate for sequence(s) of type: ", $builder->type);

        # Set up a request for the filter script
        my $request = $builder->prepare_run;
        $request->caller_ref($caller_key);
        if ($request_adaptor->already_running($request)) {
            $self->logger->warn("Already running an exonerate with this fingerprint, type: ", $builder->type);
            next;
        }

        $request_adaptor->store($request);

        my $analysis_name = $builder->analysis_name;
        push @method_names, $analysis_name;

        # Ensure new-style columns are selected if used
        $ace_db->select_column_by_name($analysis_name);
    }

    if (@method_names) {
        $session_window->RequestQueuer->request_features(@method_names);
        $session_window->update_status_bar;
    }

    return @method_names;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
