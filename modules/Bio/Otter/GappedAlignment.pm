
### Bio::Otter::GappedAlignment

package Bio::Otter::GappedAlignment;

use strict;
use warnings;

use Bio::Otter::GappedAlignment::Element;

use Readonly;

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

sub split_by_transcript_exons {
    my ($self, $transcript) = @_;

    if ($transcript->strand == -1) {
        warn "Can't handle reverse strand transcript yet";
        return;
    }

    print "Considering transcript ", $transcript->start, " - ", $transcript->end,
          "\t(", ref($transcript), ")\n";
    print "            alignment  ", $self->target_start, " - ", $self->target_end, "\n";

    my $offset = $transcript->start;

    my @exons = $transcript->get_all_Exons;

    my @elements = ( @{$self->elements} ); # make a copy we can consume
    return unless @elements;

    my @split;

    my $t_splice_curr = $self->target_start; # current spliced target pos
    my $t_split_curr  = $t_splice_curr;      # current split target start pos
    my $t_split_end   = $self->target_end;   # current split target end pos

    my $prev_exon;

    EXON: foreach my $exon (@exons) {

        if ($prev_exon) {
            my $intron_len = $exon->start - $prev_exon->end - 1;
            $t_split_curr += $intron_len;
            $t_split_end  += $intron_len;
            print "Adjusting for intron ", $prev_exon->end+1, "-", $exon->start-1, " len ", $intron_len, "\n";
        }

        print "Considering exon ", $exon->start, " - ", $exon->end, "\t(", ref($exon), ")\n";

        my $e_start = $exon->start - $offset;
        my $e_end   = $exon->end   - $offset;

        print " Moved to        ", $e_start,      " - ", $e_end, "\n";
        print " CF t_split ",      $t_split_curr, " - ", $t_split_end, " :\t";

        if ($e_end   < $t_split_curr) { print "not there yet\n"; next EXON }
        if ($e_start > $t_split_end)  { print "beyond\n";        next EXON }

        print "in alignment\n";

        my $exon_ga = $self->_new;

      ELEMENTS: while (my $ele = shift @elements) {

          if (($t_split_curr + $ele->target_length - 1) <= $e_end) {

              # Whole ele fits in exon, add a copy
              print "Adding whole element\n";

              $exon_ga->add_element($ele->make_copy);
              $t_split_curr += $ele->target_length;

          } else {

              # Time to split an element
              print "Should split here\n";

              # ...do splitting, put remainder back

              unshift @elements, $ele;
              last ELEMENTS;
          }

      } # ELEMENTS

        print "Have exon alignment: ", $exon_ga->vulgar_comps_string, "\n";
        push @split, $exon_ga;

        $prev_exon = $exon;

    } # EXONS

    print "Done";
    return;
}

sub vulgar_comps_string {
    my $self = shift;
    return unless $self->n_elements;

    my @ele_strings = map { $_->string } @{$self->elements};
    return join(' ', @ele_strings);
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
    if ($query_start) {
        $self->{'_query_start'} = $query_start;
    }
    return $self->{'_query_start'};
}

sub query_end {
    my ($self, $query_end) = @_;
    if ($query_end) {
        $self->{'_query_end'} = $query_end;
    }
    return $self->{'_query_end'};
}

sub query_strand {
    my ($self, $query_strand) = @_;
    if ($query_strand) {
        $self->{'_query_strand'} = $query_strand;
    }
    return $self->{'_query_strand'};
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
    if ($target_start) {
        $self->{'_target_start'} = $target_start;
    }
    return $self->{'_target_start'};
}

sub target_end {
    my ($self, $target_end) = @_;
    if ($target_end) {
        $self->{'_target_end'} = $target_end;
    }
    return $self->{'_target_end'};
}

sub target_strand {
    my ($self, $target_strand) = @_;
    if ($target_strand) {
        $self->{'_target_strand'} = $target_strand;
    }
    return $self->{'_target_strand'};
}

sub score {
    my ($self, $score) = @_;
    if ($score) {
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

sub n_elements {
    my $self = shift;
    return scalar @{$self->elements};
}
    
sub _clear_elements {
    my $self = shift;
    return $self->{'_elements'} = [];
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
