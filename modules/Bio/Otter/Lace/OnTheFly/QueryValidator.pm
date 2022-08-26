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

### Bio::Otter::Lace::OnTheFly::QueryValidator

package Bio::Otter::Lace::OnTheFly::QueryValidator;

use namespace::autoclean;
use Moose;

with 'MooseX::Log::Log4perl';

use Carp;
use List::MoreUtils qw{ uniq };

use Bio::Otter::Lace::OnTheFly::Utils::SeqList;
use Bio::Otter::Lace::OnTheFly::Utils::Types;
use Bio::Otter::Lace::Client;
use Hum::FastaFileIO;
use Bio::Vega::Evidence::Types qw{ new_evidence_type_valid seq_is_protein };

has accession_type_cache => ( is => 'ro', isa => 'Bio::Otter::Lace::AccessionTypeCache', required => 1 );

has seqs                 => ( is => 'ro', isa => 'ArrayRef[Hum::Sequence]', default => sub{ [] } );
has accessions           => ( is => 'ro', isa => 'ArrayRef[Str]',           default => sub{ [] } );

has sequence_type      => ( is => 'ro', isa => 'Str', default => 'dna');

has lowercase_poly_a_t_tails => ( is => 'ro', isa => 'Bool', default => undef );

has problem_report_cb    => ( is => 'ro', isa => 'CodeRef', required => 1 );
has long_query_cb        => ( is => 'ro', isa => 'CodeRef', required => 1 );
has progress_cb          => ( is => 'ro', isa => 'CodeRef' );

has max_query_length     => ( is => 'ro', isa => 'Int', default => 10000 );

has confirmed_seqs       => (
    is       => 'ro',
    isa      => 'SeqListClass',
    lazy     => 1,
    builder  => '_build_confirmed_seqs',
    init_arg => undef,
    handles  => [qw( seqs_by_name seq_by_name )],
    );

has seqs_by_type         => ( is => 'ro', isa => 'HashRef[ArrayRef[Hum::Sequence]]',
                              lazy => 1, builder => '_build_seqs_by_type', init_arg => undef );

# Internal attributes
#
has _acc_type_full_cache => ( is => 'ro', isa => 'HashRef[ArrayRef[Str]]',
                              default => sub{ {} }, init_arg => undef );

has _warnings            => ( is => 'ro', isa => 'HashRef', default => sub{ {} }, init_arg => undef );

sub BUILD {
    my $self = shift;
    # not sure how much processing to do here
    # none for now, only if it becomes necessary for multiple methods
    return;
}

sub _build_confirmed_seqs {     ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;

    {
        my @seq_accs      = map { $_->name } @{$self->seqs};
        my @supplied_accs = @{$self->accessions};

        # We work on the union of the supplied sequences and supplied accession ids
        my @accessions = ( @seq_accs, @supplied_accs );
        return Bio::Otter::Lace::OnTheFly::Utils::SeqList->new( seqs => [] ) unless @accessions; # nothing to do

        $self->logger->debug('n(accessions) = ', scalar @accessions);

        # identify the types of all the accessions supplied
        my $cache = $self->accession_type_cache;
        # The populate method will fetch the latest version of
        # any accessions which are supplied without a SV into
        # the cache object.
        &{$self->progress_cb}('Fetching accession info') if $self->progress_cb;
        $cache->populate(\@accessions);
    }

    my $seq_type = $self->sequence_type;
    $self->_augment_supplied_sequences;
    my @to_fetch = $self->_check_augment_supplied_accessions;
    $self->_fetch_sequences($seq_type, @to_fetch);

    # tell the user about any missing sequences or remapped accessions

    # might it be better to pass the unprocessed warning lists to the callback and let
    # them be processed according to the context and graphics framework?

    if (%{$self->_warnings}) {
        my $formatted_msgs = $self->_format_warnings;
        &{$self->problem_report_cb}( $formatted_msgs );
    }

    # check for unusually long query sequences

    my @confirmed_seqs;

    for my $seq (@{$self->seqs}) {
        if ($seq->sequence_length > $self->max_query_length) {
            my $okay = &{$self->long_query_cb}( {
                name   => $seq->name,
                length => $seq->sequence_length,
                                                 } );
            if ($okay) {
                push @confirmed_seqs, $seq;
            }
        }
        else {
            push @confirmed_seqs, $seq;
        }
    }

    if ($self->lowercase_poly_a_t_tails) {
        for my $seq (@confirmed_seqs) {
            my $s = $seq->uppercase;
            $s =~ s/(^T{6,}|A{6,}$)/lc($1)/ge;
            $seq->sequence_string($s);
        }
    }

    return Bio::Otter::Lace::OnTheFly::Utils::SeqList->new( seqs => \@confirmed_seqs );
}

sub _build_seqs_by_type {       ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my %seqs_by_type;
    foreach my $seq (@{$self->confirmed_seqs->seqs}) {
        my $type = $seq->type;
        unless ($type && new_evidence_type_valid($type))
        {
            unless ($type =~ /^OTF_AdHoc_/) { # may be already set by EditWindow::Exonerate->entered_seqs()
                $type = seq_is_protein($seq->sequence_string) ? 'OTF_AdHoc_Protein' : 'OTF_AdHoc_DNA';
            }
        }
        push @{ $seqs_by_type{ $type } }, $seq;
    }

    return \%seqs_by_type;
}

sub seq_types {
    my $self = shift;
    return keys %{$self->seqs_by_type};
}

sub seqs_for_type {
    my ($self, $type) = @_;
    return $self->seqs_by_type->{$type};
}

# add type and full accession information to the supplied sequences
# modifies sequences in $self->seqs
#
sub _augment_supplied_sequences {
    my $self = shift;

    for my $seq (@{$self->seqs}) {
        my $name = $seq->name;
        my $entry = $self->_acc_type_full($name);
        if ($entry) {
            my ($type, $full_acc) = @$entry;
            ### Might want to be paranoid and check that the sequence of
            ### supplied sequences matches the pfetched sequence where the
            ### names of sequences are public accessions.
            $seq->type($type);
            $seq->name($full_acc);
            if ($name ne $full_acc) {
                $self->_add_remap_warning( $name => $full_acc );
            }
        } else {
            $self->_save_seq_to_acc_info($seq);
        }
    }
    return;
}

sub _check_augment_supplied_accessions {
    my $self = shift;

    my $supplied_accs = $self->accessions;

    my @to_fetch;
    foreach my $acc ( @$supplied_accs ) {

        my $entry = $self->_acc_type_full($acc);

        unless ($entry) {
            # No point trying to fetch invalid accessions
            $self->_add_missing_warning($acc, "unknown accession or illegal evidence type");
            next;
        }

        my ($type, $full) = @$entry;
        if ($type eq 'SRA') {
            $self->_add_missing_warning($acc, 'illegal evidence type: SRA');
            next;
        }

        push(@to_fetch, $full);

        if ($acc ne $full) {
            $self->_add_remap_warning( $acc => $full );
        }

    }
    return @to_fetch;
}

sub Client {
    my ($self, $client) = @_;

    if ($client) {
        $self->{'_Client'} = $client;
        $self->colour( $self->next_session_colour );
    }
    return $self->{'_Client'};
}

# Adds sequences to $self->seqs
#
sub _fetch_sequences {
    my ($self, $seq_type, @to_fetch) = @_;

    my $cache = $self->accession_type_cache;

    @to_fetch = uniq @to_fetch;
    $self->logger->debug('Need seq for: ', join(',', @to_fetch) || '<none>');
    my $client = Bio::Otter::Lace::Defaults::make_Client();
    foreach my $acc (@to_fetch) {

        my $seq = $client->fetch_fasta_seqence($acc, $seq_type);
        if (substr($seq, 0, 1) eq ">") {
          $seq = $self->parse_fasta_sequence($seq);
          push(@{$self->seqs}, $seq);
          my ($type, $full) = @{$self->_acc_type_full($acc)};
          unless ($type) {
              $self->_add_missing_warning($acc => 'illegal evidence type');
              next;
          }

          if($seq_type eq 'protein' && $type ne 'Protein') {
              $self->_add_accession_type_warning($acc, " Evidence $type and manual $seq_type type mismatch");
              next;
          }

          $seq->type($type);
          $seq->name($acc);
        } else {
          $self->_add_missing_warning($acc, "unknown accession or illegal evidence type");
        }

#        my ($type, $full) = @{$self->_acc_type_full($acc)};
#        unless ($type) {
#            $self->_add_missing_warning($acc => 'illegal evidence type');
#            next;
#        }

#        my $info = $cache->feature_accession_info($acc);
#        unless ($info) {
#            $self->logger->error("No info for '$acc' - this should not happen");
#            $self->_add_missing_warning($acc => 'internal error');
#            next;
#        }

#        unless ($info->{currency} and $info->{currency} eq 'current') {
#            $self->_add_missing_warning($acc => 'obsolete SV');
#            next;
#        }

#        unless ($info->{sequence}) {
#            $self->_add_missing_warning($acc => 'no sequence');
#            next;
#        }

#        my $seq = Hum::Sequence->new;
#        $seq->name($full);
#        $seq->type($type);
#        $seq->sequence_string($info->{sequence});

#        # Will this ever get hit?
#        if ($full ne $acc) {
#            $self->logger->error("_fetch_sequences called with partial acc.sv for '$acc','$full'");
#            $self->_add_remap_warning($acc => $full);
#        }

#        push(@{$self->seqs}, $seq);
    }

    return;
}

sub parse_fasta_sequence {
    my ($self, $raw_seq) = @_;

      my @seqs;
      $raw_seq = $self->_tidy_sequence($raw_seq);
      push @seqs, Hum::FastaFileIO->new(\$raw_seq)->read_all_sequences;
        # Make sure entered seqs are distinct from seqs fetched by accession.
        # (We could try to lookup and compare, as a future feature.)
      foreach my $seq (@seqs) {
        my $name = $seq->name;
        unless ($name =~ /^otf[_:]/i) {
            $seq->name($name);
        }
        $seq->type(seq_is_protein($seq->sequence_string) ? 'Protein' : 'DNA');
      }

      return $seqs[0];
}

sub _tidy_sequence {
    my ($self, $seq) = @_;
    open my $fh, '<', \$seq or $self->logger->logdie('open stringref failed');
    my @stripped;
    while (my $line = <$fh>) {
        chomp $line;
        unless ($line =~ /^>/) {
            $line =~ s{       # strip leading line numbers:
                          ^   #   start of line
                          \s* #   optional leading whitespace
                          \d+ #   line number
                          \s+ #   at least some whitespace
                      }{}x;
            $line =~ s/\s+//g; # strip whitespace
        }
        push @stripped, $line if $line;
    }
    push @stripped, '';         # ensure trailing newline
    return join("\n", @stripped);
}

# implements the local micro-cache - including caching misses

sub _acc_type_full {
    my ($self, $acc) = @_;

    my $local_cache = $self->_acc_type_full_cache;
    if (exists $local_cache->{$acc}) {
        my $cached_entry = $local_cache->{$acc};
        return $cached_entry;
    }

    my ($type, $full) = $self->accession_type_cache->type_and_name_from_accession($acc);
    my $new_entry;
    $new_entry = [ $type, $full ] if ($type and $full);
    return $local_cache->{$acc} = $new_entry;
}

sub _save_seq_to_acc_info {
    my ($self, $seq) = @_;

    my $local_cache = $self->_acc_type_full_cache;
    my $name = $seq->name;
    my $type = $seq->type;

    if ($local_cache->{$name}) {
        $self->logger->warn("_save_seq_to_acc_info: replacing entry for '$name'");
    }

    my $entry = {
        acc_sv          => $name,
        # taxon_id
        evi_type        => $type,
        description     => $seq->description || 'User-supplied sequence for on-the-fly alignment',
        source          => $type,
        # currency
        sequence_length => $seq->sequence_length,
        sequence        => $seq->sequence_string,
    };
    $self->accession_type_cache->save_accession_info($entry);
    return $local_cache->{$name} = [ $type, $name ];
}

# warnings

sub _add_warning {
    my ($self, $type, $warning) = @_;
    my $list = $self->_warnings->{$type} ||= [];
    push @{$list}, $warning;
    return;
}

sub _add_remap_warning {
    my ($self, $old, $new) = @_;
    my $remap_warnings = $self->_warnings->{remapped} ||= [];
    $self->_add_warning( remapped => [ $old => $new ] );
    return;
}

sub _add_missing_warning {
    my ($self, $acc, $msg) = @_;
    $self->_add_warning( missing => [ $acc => $msg ] );
    return;
}

sub _add_accession_type_warning {
    my ($self, $acc, $msg) = @_;
    $self->_add_warning( accession_type => [ $acc => $msg ] );
    return;
}

# FIXME: remove, and related 'unclaimed' warning handling
#
# sub _add_unclaimed_warning {
#     my ($self, $acc) = @_;
#     $self->_add_warning( unclaimed => $acc );
#     return;
# }

sub _format_warnings {
    my $self = shift;
    my $warnings = $self->_warnings;

    my ($missing_msg, $remapped_msg, $unclaimed_msg, $accession_type_msg) = ( ('') x 3 );

    if ($warnings->{accession_type}) {
        my @accession_type = @{$warnings->{accession_type}};
        $accession_type_msg = join("\n", map { sprintf("  %s %s", @{$_}) } @accession_type);
        $accession_type_msg =
            "The following sequences were fetched, type mismatch:\n\n$accession_type_msg\n"
    }

    if ($warnings->{missing}) {
        my @missing = @{$warnings->{missing}};
        $missing_msg = join("\n", map { sprintf("  %s %s", @{$_}) } @missing);
        $missing_msg =
            "I did not find any sequences for the following accessions:\n\n$missing_msg\n"
    }

    if ($warnings->{remapped}) {
        my @remapped = @{$warnings->{remapped}};
        $remapped_msg = join("\n", map { sprintf("  %s to %s", @{$_}) } @remapped);
        $remapped_msg =
            "The following supplied accessions have been mapped to full ACCESSION.SV:\n\n$remapped_msg\n"
    }

    if ($warnings->{unclaimed}) {
        my @unclaimed = @{$warnings->{unclaimed}};
        $unclaimed_msg =
            "The following sequences were fetched, but didn't map back to supplied names:\n\n"
            . join('', map { "  $_\n" } @unclaimed);
    }
    return( {
        missing        => $missing_msg,
        remapped       => $remapped_msg,
        unclaimed      => $unclaimed_msg,
        accession_type => $accession_type_msg,
            } );
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
