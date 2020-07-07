=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### Bio::Otter::GappedAlignment

package Bio::Otter::GappedAlignment;

use strict;
use warnings;

use Bio::Otter::GappedAlignment::Element;

use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;

use Bio::Otter::Log::Log4perl 'logger';

use parent 'Bio::Otter::Vulgar';

sub _new {
    my ($class, %attrs) = @_;

    my $pkg = ref($class) || $class;
    my $self = $pkg->SUPER::new(%attrs);

    $self->_clear_elements;

    return $self;
}

sub _new_copy_basics {
    my $self = shift;

    my $new = $self->SUPER::copy;
    $new->_clear_elements;

    return $new;
}

sub from_vulgar {
    my ($pkg, $vulgar_string) = @_;
    return $pkg->_parse_vulgar(vulgar_string => $vulgar_string);
}

sub from_vulgar_comps_string {
    my ($pkg, $vulgar_comps_string) = @_;
    return $pkg->_parse_vulgar(vulgar_comps_string => $vulgar_comps_string);
}

sub _parse_vulgar {
    my ($pkg, @args) = @_;

    my $self = $pkg->_new(@args);

    $self->parse_align_comps(   # in parent Bio::Otter::Vulgar
        sub {
            my ($type, $q_len, $t_len) = @_;
            my $element = Bio::Otter::GappedAlignment::Element->new($type, $q_len, $t_len);
            $self->add_element($element);
        }
        ) or $self->logger->logconfess('parse_align_comps() failed');

    return $self;
}

=head2 intronify_by_transcript_exons

Insert introns into the alignment according to the exon boundaries in the supplied transcript.

=cut

sub intronify_by_transcript_exons {
    my ($self, $transcript) = @_;

    return unless @{$self->elements};

    $self->logger->logcroak('Already contains introns') if $self->has_introns;

    $self->logger->debug("Intronify for q:'", $self->query_id, "', t: '", $self->target_id, "'");
    $self->logger->debug("   vulgar comps: ", $self->vulgar_comps_string);

    my $intron_ga;

    if ($self->target_strand eq '-') {

        my $reversed = $self->reverse_alignment;
        $intron_ga = $reversed->_do_intronify($transcript);

        $intron_ga = $intron_ga->reverse_alignment;

    } else {
        $intron_ga = $self->_do_intronify($transcript);
    }

    return $intron_ga;
}

# Switcher
#
sub _do_intronify {
    my ($self, $transcript) = @_;

    my $class = ref($transcript);
    $self->logger->logcroak('$transcript must be an object') unless $class;

    return $self->_do_intronify_from_HumAceSubSeq($transcript)      if $transcript->isa('Hum::Ace::SubSeq');
    return $self->_do_intronify_from_EnsEMBLTranscript($transcript) if $transcript->isa('Bio::EnsEMBL::Transcript');

    $self->logger->logcroak("Unknown transcript object type '$class'");
    return;
}

sub _do_intronify_from_HumAceSubSeq {
    my ($self, $subseq) = @_;

    my $ts_start  = $subseq->start;
    my $ts_end    = $subseq->end;
    my $ts_strand = $subseq->strand;

    my $exons = [ $subseq->get_all_Exons_in_transcript_order ];

    return $self->_really_do_intronify($ts_start, $ts_end, $ts_strand, $exons);
}

sub _do_intronify_from_EnsEMBLTranscript {
    my ($self, $transcript) = @_;

    my $ts_start  = $transcript->start;
    my $ts_end    = $transcript->end;
    my $ts_strand = $transcript->strand;

    my $exons = $transcript->get_all_Exons;

    return $self->_really_do_intronify($ts_start, $ts_end, $ts_strand, $exons);
}

sub _really_do_intronify {
    my ($self, $ts_start, $ts_end, $ts_strand, $exons) = @_;

    $self->logger->debug("Considering transcript ", $ts_start, " - ", $ts_end, " (", $ts_strand, ")");
    $self->logger->debug("            alignment  ", $self->target_start+1, " - ", $self->target_end,
                         " (", $self->target_strand, ")");

    my %data;
    my $intron_ga;

    $data{elements}               = [ @{$self->elements} ];  # make a copy we can consume
    $data{intron_ga} = $intron_ga = $self->_new_copy_basics; # this is what we're building!

    $data{protein_query} = $self->query_is_protein;

    # $data{offset} is offset between transcript in genomic or clone coords, and spliced transcript (cDNA)

    if ($ts_strand == 1) {
        $data{fwd} = 1;
        $data{offset} = $ts_start - 1; # transcript is base 1
    } elsif ($ts_strand == -1) {
        $data{offset} = $ts_end + 1;
        $intron_ga->swap_target_strand;
    } else {
        $self->logger->logcroak("Illegal transcript strand value '$ts_strand'");
    }

    $data{t_splice_pos} = $self->target_start+1; # current spliced target pos, base 1

    $self->_walk_exons($exons, \&_intronify_do_exon, \&_intronify_do_intron, \%data);

    $self->logger->debug("Done (offset $data{offset})");

    $self->_verify_intronified_lengths($intron_ga) if $self->logger->is_debug;

    return $intron_ga;
}

sub _walk_exons {
    my ($self, $exons, $exon_callback, $intron_callback, $data) = @_;

    my $prev_exon;

  EXON: foreach my $exon (@$exons) {

      if ($prev_exon) {

          my ($intron_start, $intron_end);
          if ($prev_exon->end < $exon->start) { # forward
              $intron_start = $prev_exon->end + 1;
              $intron_end   = $exon->start - 1;
          } else {                              # reverse
              $intron_start = $exon->end + 1;
              $intron_end   = $prev_exon->start - 1;
          }

          $self->logger->debug("Processing intron ", $intron_start, "-", $intron_end,
                               " len ", $intron_end - $intron_start + 1);

          $intron_callback->($self, $intron_start, $intron_end, $data);
      }
      $prev_exon = $exon;

      $self->logger->debug("Processing exon ", $exon->start, " - ", $exon->end, "\t(", ref($exon), ")");

      $exon_callback->($self, $exon, $data);

  } # EXON

    return;
}

sub _intronify_do_exon {
    my ($self, $exon, $data) = @_;

    my ($e_start, $e_end);
    if ($data->{fwd}) {
        $e_start = $exon->start - $data->{offset};
        $e_end   = $exon->end   - $data->{offset};
    } else {
        $e_start = $data->{offset} - $exon->end;
        $e_end   = $data->{offset} - $exon->start;
    }

    $self->logger->debug(" Moved to        ", $e_start,      " - ", $e_end, " (offset ", $data->{offset}, ")");
    $self->logger->debug(" CF t_splice     ", $data->{t_splice_pos}, " - ", $self->target_end, " :");

    if ($e_end   < $data->{t_splice_pos}) {
        $self->logger->debug("  not there yet");
        return;
    }
    if ($e_start > $self->target_end) {
        $self->logger->debug("  beyond");
        return;
    }

    $self->logger->debug("  in alignment");

    my $intron_ga = $data->{intron_ga};

    my $t_split_pos;
    if ($data->{fwd}) {
        $t_split_pos = $data->{t_splice_pos} + $data->{offset} - 1;
    } else {
        $t_split_pos = $data->{offset} - $data->{t_splice_pos};
    }

    unless ($data->{in_alignment}) {
        # First time in
        $data->{in_alignment} = 1;
        $intron_ga->target_start($t_split_pos);
        # $intron_ga->query_start unchanged
        $intron_ga->target_end($intron_ga->target_start); # will be updated by add_element_track_lengths()
        $intron_ga->query_end( $intron_ga->query_start ); # --"--
        $data->{query_pos} = $self->query_start;
    }

  ELEMENTS: while (my $ele = shift @{$data->{elements}}) {

      $self->logger->debug("Considering: ", $ele->string);

      if ($ele->is_intronic) {
          $self->logger->logcroak(sprintf 'Alignment already contains intronic element (%s)', $ele->string);
      }

      my $overlap = $e_end - $data->{t_splice_pos} + 1;

      if ($ele->target_length <= $overlap) {

          # Whole ele fits in exon, add a copy
          $self->logger->debug("Adding whole element");

          $intron_ga->add_element_track_lengths($ele->make_copy);
          $data->{t_splice_pos} += $ele->target_length;
          $data->{query_pos}    += $ele->query_length * $intron_ga->query_strand_sense;

      } elsif ($overlap > 0) {

          # Time to split an element
          # ...do splitting, put remainder back
          $self->logger->debug("Adding ", $overlap, " of ", $ele->target_length);

          my ($in_exon_eles, $remaining_eles) = $ele->divide($overlap, $data->{protein_query});

          foreach my $ele (@{$in_exon_eles}) {
              $intron_ga->add_element_track_lengths($ele);

              $data->{t_splice_pos} += $ele->target_length;
              $data->{query_pos}    += $ele->query_length * $intron_ga->query_strand_sense;
          }
          unshift @{$data->{elements}}, @{$remaining_eles};

          last ELEMENTS;

      } else {
          # Put whole element back for next time
          unshift @{$data->{elements}}, $ele;
          last ELEMENTS;
      }

  } # ELEMENTS

    $self->logger->debug("Have alignment: ", $intron_ga->vulgar_comps_string);

    if ($data->{in_alignment} and not @{$data->{elements}}) {
        $self->logger->debug("Ran out of elements so no longer in alignment");
        $data->{in_alignment} = 0;
    }

    return;
}

sub _intronify_do_intron {
    my ($self, $start, $end, $data) = @_;

    my $length = $end - $start + 1;

    if ($data->{fwd}) {
        $data->{offset} += $length;
    } else {
        $data->{offset} -= $length;
    }

    if ($data->{in_alignment}) {
        my $intron = Bio::Otter::GappedAlignment::Element::Intron->new(0, $length);
        $data->{intron_ga}->add_element_track_lengths($intron);
    }

    return;
}

# N.B.: vulgar_comps_string and vulgar_string CANNOT be taken directly from $self->vulgar,
#       as here the list of GappedAlignment::Element's is primary.

sub vulgar_comps_string {
    my $self = shift;
    return unless $self->n_elements;

    my @ele_strings = map { $_->string } @{$self->elements};
    return join(' ', @ele_strings);
}

sub align_comps_string {
    my $self = shift;
    return $self->vulgar_comps_string;
}

sub vulgar_string {
    my $self = shift;
    return unless $self->n_elements;

    my $sugar_string        = $self->sugar_string;
    my $vulgar_comps_string = $self->vulgar_comps_string;

    return "$sugar_string $vulgar_comps_string";
}

sub string {
    my $self = shift;
    return $self->vulgar_string;
}

sub _coalesce_cigar_strings {
    my ($self, $ele_type_sub, $ele_format_sub) = @_;

    my @elements = ( @{$self->elements} ); # make a copy to consume
    my @ele_strings;
    while (my $this_ele = shift @elements) {
        my $length = $this_ele->cigar_length;
        my $next_ele;
        while (     $next_ele = $elements[0]
                and $ele_type_sub->($this_ele) eq $ele_type_sub->($next_ele) )
        {
            $length += $next_ele->cigar_length; # combine
            shift @elements;                    # and discard
        }
        my $cigar_string = $ele_format_sub->($this_ele, $length, $self);
        push @ele_strings, $cigar_string;
    }
    return @ele_strings;
}

sub ensembl_cigar_string {
    my $self = shift;
    return unless $self->n_elements;

    my @ele_strings = $self->_coalesce_cigar_strings(
        sub { return shift->ensembl_cigar_type; },
        sub {
            my ($ele, $length, $ga) = @_;
            my $type = $ele->ensembl_cigar_type;
            if (   ($type eq 'D' and     $ga->query_is_protein  and not($ga->target_is_protein))
                or ($type eq 'I' and not($ga->query_is_protein) and     $ga->target_is_protein) )
            {
                $length *= 3;   # peptide -> nucleotide
            }
            return ($length > 1 ? $length : '') . $type;
        },
        );
    return join('', @ele_strings);
}

sub exonerate_cigar_string {
    my $self = shift;
    return unless $self->n_elements;

    my @ele_strings = $self->_coalesce_cigar_strings(
        sub { return shift->cigar_type; },
        sub { my ($ele, $length) = @_; return $ele->cigar_type . ' ' . $length; },
        );
    return join(' ', @ele_strings);
}

# Should these ensembl_* methods be mixed in via a separate module, rather than embedded?
#
sub vega_features {
    my $self = shift;
    return $self->_ensembl_like_features('vega_feature');
}

sub ensembl_features {
    my $self = shift;
    return $self->_ensembl_like_features('ensembl_feature');
}

sub _ensembl_like_features {
    my ($self, $method) = @_;
    return unless $self->n_elements;

    my @egas = $self->exon_gapped_alignments;
    return unless @egas;

    @egas = map { $_->_split_at_frameshifts } @egas;

    my @ensembl_features;
    foreach my $ega (@egas) {
        next unless $ega;
        push @ensembl_features, $ega->_strip_for_ensembl->$method();
    }

    return @ensembl_features;
}

sub vega_feature {
    my $self = shift;
    my $af_type = $self->query_is_protein ? 'Bio::Vega::DnaPepAlignFeature' : 'Bio::Vega::DnaDnaAlignFeature';
    return $self->_ensembl_like_feature($af_type);
}

sub ensembl_feature {
    my $self = shift;
    my $af_type = $self->query_is_protein ? 'Bio::EnsEMBL::DnaPepAlignFeature' : 'Bio::EnsEMBL::DnaDnaAlignFeature';
    return $self->_ensembl_like_feature($af_type);
}

sub _ensembl_like_feature {
    my ($self, $af_type) = @_;
    return unless $self->n_elements;

    my ($t_start, $t_end, $t_strand) = $self->target_ensembl_coords;
    my ($q_start, $q_end, $q_strand) = $self->query_ensembl_coords;

    return $af_type->new(
        -seqname      => $self->target_id,
        -start        => $t_start,
        -end          => $t_end,
        -strand       => $t_strand,
        -hseqname     => $self->query_id,
        -hstart       => $q_start,
        -hend         => $q_end,
        -hstrand      => $q_strand,
        -score        => $self->score,
        -percent_id   => $self->percent_id,
        -cigar_string => $self->ensembl_cigar_string,
        );
}

sub _split_at_frameshifts {
    my $self = shift;
    my @elements = @{$self->elements};
    return $self unless grep { $_->type eq 'F' } @elements;

    my $target_pos = $self->target_start;
    my $query_pos  = $self->query_start;

    my @splits;
    my $current;

    while (my $ele = shift @elements) {
        if ($ele->type eq 'F') {
            if ($current) {
                push @splits, $current;
                $current = undef;
            }
        } else {
            unless ($current) {
                $current = $self->_new_copy_basics;
                $current->target_start($target_pos);
                $current->query_start( $query_pos);
                $current->target_end($target_pos); # will be updated by add_element_track_lengths()
                $current->query_end( $query_pos);  # --"--
            }
            $current->add_element_track_lengths($ele);
        }
        $target_pos += $self->target_strand_sense * $ele->target_length;
        $query_pos  += $self->query_strand_sense  * $ele->query_length;
    }
    push @splits, $current if $current;

    return @splits;
}

# Remove split codons (which will be at ends) and leading or trailing indels
#
sub _strip_for_ensembl {
    my $self = shift;

    my $stripped = $self->_new_copy_basics;
    my $elements = $stripped->{_elements} = [ @{$self->elements} ];

    # Should these strip repeatedly in a while loop?

    if ($elements->[0] and ($elements->[0]->type eq 'S' or $elements->[0]->type eq 'G')) {
        my $sc = shift(@$elements);
        $stripped->target_start($self->target_start + $self->target_strand_sense * $sc->target_length);
        $stripped->query_start( $self->query_start  + $self->query_strand_sense  * $sc->query_length);
    }

    if ($elements->[-1] and ($elements->[-1]->type eq 'S' or $elements->[-1]->type eq 'G')) {
        my $sc = pop(@$elements);
        $stripped->target_end($self->target_end - $self->target_strand_sense * $sc->target_length);
        $stripped->query_end( $self->query_end  - $self->query_strand_sense  * $sc->query_length);
    }

    return $stripped;
}

sub reverse_alignment {
    my $self = shift;

    my $reversed = $self->_new_copy_basics;
    $reversed->swap_query_strand;
    $reversed->swap_target_strand;
    $reversed->swap_gene_orientation;
    $reversed->{_elements} = [ reverse @{$self->elements} ];

    return $reversed;
}

sub query_length {
    my $self = shift;
    return $self->_length($self->query_start, $self->query_end);
}

sub target_length {
    my $self = shift;
    return $self->_length($self->target_start, $self->target_end);
}

sub _length {
    my ($self, $start, $end) = @_;
    return abs($end - $start);
}

sub swap_query_strand {
    my $self = shift;
    my $sense = $self->query_strand_sense;
    $sense *= -1;
    if (   ($sense > 0 and $self->query_start > $self->query_end)
        or ($sense < 0 and $self->query_start < $self->query_end)) {
        # Swap start and end coords
        my $tmp = $self->query_start;
        $self->query_start($self->query_end);
        $self->query_end($tmp);
    }
    return $self->query_strand($sense);
}

sub swap_target_strand {
    my $self = shift;
    my $sense = $self->target_strand_sense;
    $sense *= -1;
    if (   ($sense > 0 and $self->target_start > $self->target_end)
        or ($sense < 0 and $self->target_start < $self->target_end)) {
        # Swap start and end coords
        my $tmp = $self->target_start;
        $self->target_start($self->target_end);
        $self->target_end($tmp);
    }
    return $self->target_strand($sense);
}

sub swap_gene_orientation {
    my $self = shift;
    return unless defined $self->gene_orientation;
    return if $self->gene_orientation eq '.';
    my $sense = $self->_strand_sense('gene_orientation');
    return $self->_strand('_gene_orientation', $sense * -1);
}

sub percent_id {
    my ($self, $percent_id) = @_;
    if (defined $percent_id) {
        $self->{'_percent_id'} = $percent_id;
    }
    return $self->{'_percent_id'};
}

sub gene_orientation {
    my ($self, $gene_orientation) = @_;
    if (defined $gene_orientation) {
        $self->{'_gene_orientation'} = $gene_orientation;
    }
    return $self->{'_gene_orientation'};
}

sub elements {
    my $self = shift;
    return $self->{'_elements'};
}

sub add_element {
    my ($self, $element) = @_;
    push @{$self->elements}, $element;
    $self->_set_has_introns if $element->is_intronic;
    return $self->elements;
}

sub add_element_track_lengths {
    my ($self, $element) = @_;

    $self->add_element($element);

    $self->target_end($self->target_end + $self->target_strand_sense * $element->target_length);
    $self->query_end( $self->query_end  + $self->query_strand_sense  * $element->query_length);

    return $self->elements;
}

sub n_elements {
    my $self = shift;
    return scalar @{$self->elements};
}

sub _clear_elements {
    my $self = shift;
    return $self->{'_elements'} = [];
}

sub has_introns {
    my $self = shift;
    return $self->{_has_introns};
}

sub _set_has_introns {
    my $self = shift;
    return $self->{_has_introns} = 1;
}

sub exon_gapped_alignments {
    my ($self, $include_unmatched_introns) = @_;

    my $egas = $self->{_exon_gapped_alignments};

    if (not($egas) or ($self->vulgar_string ne $self->{_ega_fingerprint})) {
        $egas = $self->_generate_exon_gapped_alignments;
    }

    return ( @$egas ) if $include_unmatched_introns;

    my @filtered;
    foreach my $exon ( @$egas ) {
        push @filtered, $exon if $exon;
    }
    return @filtered;
}

sub _generate_exon_gapped_alignments {
    my $self = shift;

    my @egas;

    my $exon_ga;
    my $state = 'idle';
    my $q_pos = $self->query_start;
    my $t_pos = $self->target_start;

    foreach my $ele (@{$self->elements}) {

        if ($ele->is_intronic) {

            if ($state eq 'exon') {
                push @egas, $exon_ga;
                $exon_ga = undef;
            }
            $state = 'intron';

        } else {

            unless ($state eq 'exon') {
                $exon_ga = $self->_new_copy_basics; # note this naively copies score, percent_id, hcoverage, etc.
                $exon_ga->target_start($t_pos);
                $exon_ga->query_start($q_pos);
                $exon_ga->target_end($exon_ga->target_start); # will be updated by add_element_track_lengths()
                $exon_ga->query_end( $exon_ga->query_start ); # --"--
            }
            $state = 'exon';
            $exon_ga->add_element_track_lengths($ele->make_copy);
        }

        $q_pos += $self->query_strand_sense  * $ele->query_length;
        $t_pos += $self->target_strand_sense * $ele->target_length;

    }

    if ($state eq 'exon') {
        # Last one
        push @egas, $exon_ga;
    }
    return $self->_set_exon_gapped_alignments(\@egas);
}

sub _set_exon_gapped_alignments {
    my ($self, $egas) = @_;
    $self->{_ega_fingerprint} = $self->vulgar_string;
    return $self->{_exon_gapped_alignments} = $egas;
}

sub _verify_intronified_lengths {
    my ($self, $intron_ga) = @_;
    my ($q_len, $t_len) = (0, 0);
    foreach my $ega ($intron_ga->exon_gapped_alignments) {
        $q_len += $ega->query_length;
        $t_len += $ega->target_length;
    }
    if ($q_len != $self->query_length or $t_len != $self->target_length) {
        $self->logger->fatal("sum(q_len): $q_len vs q_len: ", $self->query_length)  if $q_len != $self->query_length;
        $self->logger->fatal("sum(t_len): $t_len vs t_len: ", $self->target_length) if $t_len != $self->target_length;
        $self->logger->logconfess('Intronify length mismatch');
    }
    $self->logger->debug('Lengths ok');
    return;
}

sub verify_element_lengths {
    my ($self) = @_;
    my ($q_len, $t_len) = (0, 0);
    foreach my $e ( @{$self->elements} ) {
        $q_len += $e->query_length;
        $t_len += $e->target_length;
    }
    if ($q_len != $self->query_length or $t_len != $self->target_length) {
        $self->logger->fatal("sum(q_len): $q_len vs q_len: ", $self->query_length)  if $q_len != $self->query_length;
        $self->logger->fatal("sum(t_len): $t_len vs t_len: ", $self->target_length) if $t_len != $self->target_length;
        $self->logger->logconfess('Element length mismatch');
    }
    $self->logger->debug('Element lengths ok');
    return;
}

# See perldoc Bio::EnsEMBL::Exon for ASCII art on phase and end_phase
#
sub phase {
    my ($self) = @_;
    my @elements = @{$self->elements};
    return -1 unless @elements;
    return  0 unless $elements[0]->isa('Bio::Otter::GappedAlignment::Element::SplitCodon');
    return (3 - $elements[0]->target_length);
}

sub end_phase {
    my ($self) = @_;
    my @elements = @{$self->elements};
    return -1 unless @elements;
    return  0 unless $elements[-1]->isa('Bio::Otter::GappedAlignment::Element::SplitCodon');
    return $elements[-1]->target_length;
}

sub consolidate_introns {
    my ($self) = @_;

    my $copy = $self->_new_copy_basics;

    my $prev_intronic;
    foreach my $ele ( @{$self->elements}, undef ) { # undef ele at end to force addition of trailing prev_intronic
        if ($ele and $ele->is_intronic) {
            my ($query_length, $target_length) = (0, 0);
            if ($prev_intronic) {
                $query_length  = $prev_intronic->query_length;
                $target_length = $prev_intronic->target_length;
            }
            $query_length  += $ele->query_length;
            $target_length += $ele->target_length;
            $prev_intronic = Bio::Otter::GappedAlignment::Element::Intron->new($query_length, $target_length);
        } else {
            if ($prev_intronic) {
                $copy->add_element($prev_intronic);
                $prev_intronic = undef;
            }
            $copy->add_element($ele) if $ele;
        }
    }

    return $copy;
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment

NB Coordinates are in exonerate 'in-between' system, see:
http://www.ebi.ac.uk/~guy/exonerate/exonerate.man.html

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
