
### Bio::Otter::GappedAlignment

package Bio::Otter::GappedAlignment;

use strict;
use warnings;

use Bio::Otter::GappedAlignment::Element;

use Carp;
use Readonly;

use Log::Log4perl;

Readonly our @SUGAR_ORDER => qw(
    _query_id
    _query_start
    _query_end
    _query_strand
    _target_id
    _target_start
    _target_end
    _target_strand
    _score
);

sub _new {
    my ($class, %sugar) = @_;

    my $pkg = ref($class) || $class;
    my $self = bless { %sugar }, $pkg;
    $self->_clear_elements;

    return $self;
}

sub _new_copy_basics {
    my $self = shift;

    my $new = bless { %$self }, ref($self);
    $new->_clear_elements;

    return $new;
}

sub from_vulgar {
    my ($pkg, $vulgar) = @_;

    my @vulgar_parts = split(' ', $vulgar);
    my (%sugar_result, @vulgar_comps);
    (@sugar_result{@SUGAR_ORDER}, @vulgar_comps) = @vulgar_parts;

    # FIXME: error handling on %sugar_result

    my $self = $pkg->_new(%sugar_result);

    while (@vulgar_comps) {
        my ($type, $q_len, $t_len) = splice(@vulgar_comps, 0, 3); # shift off 1st three
        unless ($type and defined $q_len and defined $t_len) {
            die "Ran out of vulgar components in mid-triplet";
        }
        my $element = Bio::Otter::GappedAlignment::Element->new($type, $q_len, $t_len);
        $self->add_element($element);
    }

    return $self;
}

=head2 intronify_by_transcript_exons

Insert introns into the alignment according to the exon boundaries in the supplied transcript.

=cut

sub intronify_by_transcript_exons {
    my ($self, $transcript, $do_per_exon) = @_;

    my $ts_strand = $transcript->strand;

    $self->logger->debug("Considering transcript ", $transcript->start, " - ", $transcript->end,
                         " (", $ts_strand, ")\t[", ref($transcript), "]");
    $self->logger->debug("            alignment  ", $self->target_start+1, " - ", $self->target_end,
                         " (", $self->target_strand, ")");

    return unless @{$self->elements};

    if ($self->target_strand eq '-') {

        my $reversed = $self->reverse_alignment;
        my ($intron_ga, $per_exon) = $reversed->intronify_by_transcript_exons($transcript, $do_per_exon);

        $intron_ga = $intron_ga->reverse_alignment;

        if ($do_per_exon) {
            my $exons = [ reverse map { $_->reverse_alignment } @$per_exon ];
            return ($intron_ga, $exons);
        } else {
            return $intron_ga;
        }
    }

    my @exons = $transcript->get_all_Exons_in_transcript_order;

    my %data;
    my $intron_ga;

    $data{elements}               = [ @{$self->elements} ];  # make a copy we can consume
    $data{intron_ga} = $intron_ga = $self->_new_copy_basics; # this is what we're building!
    $data{per_exon}               = [];

    $data{debug_exon_ga} = sub {
        my ($ga, $msg) = @_;
        $self->logger->debug(sprintf('Exon_ga %s q: %d-%d, t: %d-%d', $msg,
                                     @$ga{qw(_query_start _query_end _target_start _target_end)}));
    };

    # $data{offset} is offset between transcript in genomic or clone coords, and spliced transcript (cDNA)

    if ($ts_strand == 1) {
        $data{fwd} = 1;
        $data{offset} = $transcript->start - 1; # transcript is base 1
    } elsif ($ts_strand == -1) {
        $data{offset} = $transcript->end + 1;
        $intron_ga->swap_target_strand;
    } else {
        croak "Illegal transcript strand value '$ts_strand'";
    }

    $data{t_splice_pos} = $self->target_start+1; # current spliced target pos, base 1

    $self->_walk_exons(\@exons, \&_intronify_do_exon, \&_intronify_do_intron, \%data);

    $self->logger->debug("Done (offset $data{offset})");

    if ($do_per_exon) {
        return ($intron_ga, $data{per_exon});
    } else {
        return $intron_ga;
    }
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
        push @{$data->{per_exon}}, undef;
        return;
    }
    if ($e_start > $self->target_end) {
        $self->logger->debug("  beyond");
        push @{$data->{per_exon}}, undef;
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

    # per-exon - do it even if we don't need it

    my $exon_ga = $intron_ga->_new_copy_basics;

    $exon_ga->score(0); # cannot easily split score between exons
    $exon_ga->target_start($t_split_pos);
    $exon_ga->query_start($data->{query_pos});
    $exon_ga->target_end($exon_ga->target_start); # will be updated by add_element_track_lengths()
    $exon_ga->query_end( $exon_ga->query_start ); # --"--
    $data->{debug_exon_ga}->($exon_ga, '[initial]  ');

  ELEMENTS: while (my $ele = shift @{$data->{elements}}) {

      if ($ele->is_intronic) {
          croak sprintf 'Alignment already contains intronic element (%s)', $ele->string;
      }

      my $overlap = $e_end - $data->{t_splice_pos} + 1;

      if ($ele->target_length <= $overlap) {

          # Whole ele fits in exon, add a copy
          $self->logger->debug("Adding whole element");

          $intron_ga->add_element_track_lengths($ele->make_copy);
          $data->{t_splice_pos} += $ele->target_length;
          $data->{query_pos}    += $ele->query_length * $intron_ga->query_strand_sense;

          $exon_ga->add_element_track_lengths($ele->make_copy);
          $data->{debug_exon_ga}->($exon_ga, '[whole ele]');

      } else {

          # Time to split an element
          # ...do splitting, put remainder back
          $self->logger->debug("Adding ", $overlap, " of ", $ele->target_length);

          my ($in_exon_ele, $remaining_ele) = $ele->divide($overlap);

          $intron_ga->add_element_track_lengths($in_exon_ele);
          unshift @{$data->{elements}}, $remaining_ele;

          $data->{t_splice_pos} += $in_exon_ele->target_length;
          $data->{query_pos}    += $in_exon_ele->query_length * $intron_ga->query_strand_sense;

          $exon_ga->add_element_track_lengths($in_exon_ele->make_copy);
          $data->{debug_exon_ga}->($exon_ga, '[partial]  ');

          last ELEMENTS;
      }

  } # ELEMENTS

    $self->logger->debug("Have alignment: ", $intron_ga->vulgar_comps_string);

    if ($data->{in_alignment} and not @{$data->{elements}}) {
        $self->logger->debug("Ran out of elements so no longer in alignment");
        $data->{in_alignment} = 0;
    }

    push @{$data->{per_exon}}, $exon_ga;

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

=head2 split_by_transcript_exons

Split into individual exon alignments, one per exon in the supplied transcript.

=cut

sub split_by_transcript_exons {
    my ($self, $transcript, $include_unmatched_exons) = @_;

    my ($intronified, $per_exon) = $self->intronify_by_transcript_exons($transcript, 1);
    return ( @$per_exon ) if $include_unmatched_exons;

    my @filtered;
    foreach my $exon ( @$per_exon ) {
        push @filtered, $exon if $exon;
    }
    return @filtered;
}

sub vulgar_comps_string {
    my $self = shift;
    return unless $self->n_elements;

    my @ele_strings = map { $_->string } @{$self->elements};
    return join(' ', @ele_strings);
}

sub vulgar_string {
    my $self = shift;
    return unless $self->n_elements;

    return sprintf('%s %d %d %s %s %d %d %s %d %s',
                   $self->query_id,  $self->query_start,  $self->query_end,  $self->query_strand,
                   $self->target_id, $self->target_start, $self->target_end, $self->target_strand,
                   $self->score,
                   $self->vulgar_comps_string);
}

sub reverse_alignment {
    my $self = shift;
    my $reversed = $self->_new_copy_basics;
    $reversed->swap_query_strand;
    $reversed->swap_target_strand;
    $reversed->{_elements} = [ reverse @{$self->elements} ];
    return $reversed;
}

# FIXME: which of these should be r/w vs r/o ?

sub query_id {
    my ($self, $query_id) = @_;
    if ($query_id) {
        $self->{'_query_id'} = $query_id;
    }
    return $self->{'_query_id'};
}

sub query_start {
    my ($self, $query_start) = @_;
    if (defined $query_start) {
        $self->{'_query_start'} = $query_start;
    }
    return $self->{'_query_start'};
}

sub query_end {
    my ($self, $query_end) = @_;
    if (defined $query_end) {
        $self->{'_query_end'} = $query_end;
    }
    return $self->{'_query_end'};
}

sub query_strand {
    my ($self, $query_strand) = @_;
    return $self->_strand($query_strand, '_query_strand');
}

sub _strand {
    my ($self, $value, $key) = @_;
    if ($value) {
        unless ($value =~ /^[+-]$/) {
            if ($value == 1) {
                $value = '+';
            } elsif ($value == -1) {
                $value = '-';
            } else {
                croak "strand '$value' not valid";
            }
        }
        $self->{$key} = $value;
    }
    return $self->{$key};
}

sub query_strand_sense {
    my $self = shift;
    return $self->_strand_sense('query_strand');
}

sub _strand_sense {
    my ($self, $accessor) = @_;
    my $strand = $self->$accessor;
    return if not defined $strand;

    if ($strand eq '+') {
        return 1;
    } elsif ($strand eq '-') {
        return -1;
    } else {
        croak "$accessor not '+' or '-'";
    }
}

sub target_id {
    my ($self, $target_id) = @_;
    if ($target_id) {
        $self->{'_target_id'} = $target_id;
    }
    return $self->{'_target_id'};
}

sub target_start {
    my ($self, $target_start) = @_;
    if (defined $target_start) {
        $self->{'_target_start'} = $target_start;
    }
    return $self->{'_target_start'};
}

sub target_end {
    my ($self, $target_end) = @_;
    if (defined $target_end) {
        $self->{'_target_end'} = $target_end;
    }
    return $self->{'_target_end'};
}

sub target_strand {
    my ($self, $target_strand) = @_;
    return $self->_strand($target_strand, '_target_strand');
}

sub target_strand_sense {
    my $self = shift;
    return $self->_strand_sense('target_strand');
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

sub score {
    my ($self, $score) = @_;
    if (defined $score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'};
}

sub elements {
    my $self = shift;
    return $self->{'_elements'};
}

sub add_element {
    my ($self, $element) = @_;
    push @{$self->elements}, $element;
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

sub logger {
    return Log::Log4perl->get_logger;
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment

NB Coordinates are in exonerate 'in-between' system, see:
http://www.ebi.ac.uk/~guy/exonerate/exonerate.man.html

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
