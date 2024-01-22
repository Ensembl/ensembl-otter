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

package Bio::Otter::Lace::OnTheFly::Builder;

use namespace::autoclean;
use Moose;

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)

with 'MooseX::Log::Log4perl';

use Digest::MD5;

use Bio::Otter::Lace::OnTheFly::Utils::ExonerateFormat qw( ryo_format );
use Bio::Otter::Lace::OnTheFly::Utils::SeqList;
use Bio::Otter::Lace::OnTheFly::Utils::Types;

use Bio::Otter::Lace::DB::OTFRequest;

has type       => ( is => 'ro', isa => 'Str',                                        required => 1 );
has query_seqs => ( is => 'ro', isa => 'SeqListClass',                               required => 1, coerce => 1 );
has target     => ( is => 'ro', isa => 'Bio::Otter::Lace::OnTheFly::TargetSeq',      required => 1 );

has softmask_target => ( is => 'ro', isa => 'Bool' );

has analysis_prefix => ( is => 'ro', isa => 'Str', builder => '_build_analysis_prefix' );
sub _build_analysis_prefix { return 'OTF_' }

has options => ( is => 'ro', isa => 'HashRef', default => sub { {} } );
has query_type_options => ( is => 'ro', isa => 'HashRef[HashRef]',
                            default => sub { { dna => {}, protein => {} } } );

has default_options    => ( is => 'ro', isa => 'HashRef', init_arg => undef,
                            lazy => 1, builder => '_build_default_options' );
has default_qt_options => ( is => 'ro', isa => 'HashRef', init_arg => undef,
                            lazy => 1, builder => '_build_default_qt_options' );

has _fingerprint       => ( is => 'ro', isa => 'Str', init_arg => undef,
                            lazy => 1, builder => '_build_fingerprint' );

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

has description_for_fasta => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_description_for_fasta' );

sub _build_description_for_fasta {  ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return sprintf('query_%s', $self->analysis_name);
}

sub seqs_for_fasta {
    my $self = shift;
    return @{$self->query_seqs->seqs};
}

with 'Bio::Otter::Lace::OnTheFly::FastaFile'; # provides fasta_file()

sub is_protein {
    my $self = shift;
    my $is_protein = ($self->type =~ /protein/i);
    return $is_protein;
}

sub query_type {
    my $self = shift;
    return $self->is_protein ? 'protein' : 'dna';
}

sub prepare_run {
    my $self = shift;

    my $command = 'exonerate'; # see also Bio::Otter::Utils::About

    my $query_file  = $self->fasta_file;
    my $query_type  = $self->query_type;
    my $target_file = $self->target->fasta_file;

    my %args = (
        '--targettype' => 'dna',
        '--target'     => $target_file,
        '--querytype'  => $query_type,
        '--query'      => $query_file,
        '--ryo'        => ryo_format(),
        '--showvulgar' => 'false',
        '--showsugar'  => 'false',
        '--showcigar'  => 'false',
        %{$self->default_options},
        %{$self->default_qt_options->{$query_type}},
        %{$self->options},
        %{$self->query_type_options->{$query_type}},
        '--softmasktarget' => $self->softmask_target ? 'yes' : 'no',
        );

    my $request = Bio::Otter::Lace::DB::OTFRequest->new(
        command     => $command,
        logic_name  => $self->analysis_name,
        target_start=> $self->target->start,
        fingerprint => $self->_fingerprint,
        args        => \%args,
        );

    return $request;
}

sub analysis_name {
    my $self = shift;

    my $type   = $self->type;
    my $prefix = $self->analysis_prefix;
    if    ($type =~ /^OTF_AdHoc_/) { return $type;       }
    elsif ($type eq 'cDNA')        { return "${prefix}mRNA";  }
    else                           { return "${prefix}${type}"; }
}

sub _build_fingerprint {
    my $self = shift;
    my $ctx = Digest::MD5->new;
    foreach my $file ($self->target->fasta_file, $self->fasta_file) {
        open(my $fh, '<', $file) or $self->log->logdie("opening '$file': $!");
        $ctx->addfile($fh);
    }
    return $ctx->hexdigest;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
