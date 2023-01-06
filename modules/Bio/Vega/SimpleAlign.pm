=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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

# Bio::Vega::SimpleAlign

=head1 NAME - Bio::Vega::SimpleAlign

=head1 SYNOPSIS

See the L<Bio::SimpleAlign> docs for a synopsis. Only extensions are 
documented here.

=head1 DESCRIPTION

Multiple alignments held as a set of sequences

See L<Bio:SimpleAlign>.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=head1 SEE ALSO

L<Bio::SimpleAlign>

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

package Bio::Vega::SimpleAlign;

use strict;
use warnings;

use Readonly;

use Bio::EnsEMBL::Utils::CigarString;

use base 'Bio::SimpleAlign';

Readonly my $DEFAULT_MAX_TOLERABLE_INSERT => 3;

=head2 promote_BioSimpleAlign

 Title     : promote_BioSimpleAlign
 Usage     : my $valn = Bio::Vega::SimpleAlign->promote_BioSimpleAlign($aln, @args);
 Function  : Reincarnates a Bio::SimpleAlign object as a Bio::Vega::SimpleAlign
 Returns   : Bio::Vega::SimpleAlign
 Args      : $aln  => a Bio::SimpleAlign object
             @args => optional args, see L<new> below.

=cut

sub promote_BioSimpleAlign {
    my ($this, $align, @args) = @_;

    my $class = ref($this) || $this;
    if ($align->isa($class)) {
        # warn "SimpleAlign is already a $class"
    } else {
        ## no critic (Anacode::ProhibitRebless)
        bless $align, $class;
    }

    my ($rank, $direction) = $align->_rearrange([qw(RANK DIRECTION)], @args);
    defined $rank      && $align->rank($rank);
    defined $direction && $align->direction($direction);

    return $align;
}

=head2 new

 Title     : new
 Usage     : my $aln = new Bio::Vega::SimpleAlign();
 Function  : Creates a new simple align object
 Returns   : Bio::Vega::SimpleAlign
 Args      : -direction => 1 or -1 indicating direction of 
                           feature to target alignment
             -rank      => integer, to allow external sorts
                           to label rank of this hit

=cut

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);

    return $class->promote_BioSimpleAlign($self, @args);
}

=head2 direction

 Title     : direction
 Usage     : $myalign->direction(-1)
 Function  : Gets/sets the direction field of the alignment
 Returns   : 1 (indicating forward) or -1 (indicating reverse)
 Argument  : 1 or -1 (optional)

=cut

sub _assert_dir {
    my ($self, $dir, $desc) = @_;
    $self->throw("Must specify $desc") unless defined $dir;
    $self->throw("$desc must be -1 or 1") unless ($dir == 1 or $dir == -1);
    return;
}

sub direction {
    my ($self, $dir) = @_;

    if (defined $dir) {
        $self->_assert_dir($dir, "direction");
        $self->{_direction} = $dir;
    }

    return $self->{_direction};
}

=head2 rank

 Title     : rank
 Usage     : $myalign->rank(23)
 Function  : Gets/sets the rank field of the alignment
 Returns   : integer
 Argument  : integer (optional)

=cut

sub rank {
    my ($self, $rank) = @_;

    if (defined $rank) {
        $self->{_rank} = $rank;
    }

    return $self->{_rank};
}

=head2 ensembl_cigar_match

 Title    : ensembl_cigar_match()
 Usage    : $cigar = $align->ensembl_cigar_match()
 Function : Generates an EnsEMBL style "cigar" (Compact Idiosyncratic
            Gapped Alignment Report) string for the alignment between 
            the two sequences in the alignment.
 Args     : none
 Returns  : Cigar string

=cut

sub _check_each_seq {
    my $self = shift;
    my @seqs = $self->each_seq;
    $self->throw("Expecting myself to contain two matched sequences") unless scalar(@seqs) == 2;
    return @seqs;
}

sub ensembl_cigar_match {
    my $self = shift;

    my @seqs = $self->_check_each_seq;

    # Relies on each_seq returning two seqs in order
    my @split_seqs = map { [ split(//, $_->seq) ] } @seqs;

    my $cigar = Bio::EnsEMBL::Utils::CigarString->generate_cigar_string(@split_seqs);
    return $cigar;
}

# Not sure these are appropriate - may end up in
#     Bio::Vega::Transcript::AlignFeature
#  or Bio::Vega::SimpleAlign::FeatureToTranscript ??

=head2 underlap_length

=cut

# These are by convention (in my usage - mg13) 
# and rely on the match being run using the same convention
#
sub reference_seq {
    my $self = shift;
    return $self->get_seq_by_pos(1);
}

sub feature_seq {
    my $self = shift;
    return $self->get_seq_by_pos(2);
}


# How much dangle is there infront or behind of reference?
# $end is 'front' or 'back' and is in standard forward sense of reference (first) seq
sub _reference_dangle_length {
    my $self = shift;
    my $end = shift;

    # Assumes reference ref is in first position
    my $seq = $self->reference_seq->seq;
    my $match = '';

    if ($end eq 'front') {
        ($match) = $seq =~ /^(-*)/x;
    } elsif ($end eq 'back') {
        ($match) = $seq =~ /(-*)$/x;
    } else {
        $self->throw("Don't understand end '%s'", $end);
    }

    return length $match;
}

=head2 underlap_length

=cut

sub underlap_length {
    my $self = shift;
    return $self->_reference_dangle_length('front');
}

=head2 trailing_length

=cut

sub trailing_length {
    my $self = shift;
    return $self->_reference_dangle_length('back');
}

=head2 trailing_feature_seq

=cut

sub trailing_feature_seq {
    my $self = shift;

    my $len = $self->trailing_length;
    return unless $len;

    my $feature_seq = $self->feature_seq->seq;
    return substr($feature_seq, -$len);
}

=head2 oversize_inserts

=cut

sub _core_align {
    my $self = shift;

    my $front_dangle = $self->_reference_dangle_length('front');
    my $back_dangle  = $self->_reference_dangle_length('back');
    my $length       = length $self->reference_seq->seq;

    return $self->slice($front_dangle + 1, $length - $back_dangle);
}

sub oversize_inserts {
    my $self = shift;
    my $max_insert = shift || $DEFAULT_MAX_TOLERABLE_INSERT;

    my $core = $self->_core_align;
    my $core_ref = $core->reference_seq->seq;

    my @os_inserts = ($core_ref =~ m/(-{$max_insert,})/gx);

    return @os_inserts;
}

=head2 split_exons

Assumes exon list is pre-processed to reference the start of the reference seq.
$exons is arrayref of arrayrefs which are ordered contiguous pairs of (start, end)
=cut

sub split_exons {
    my $self  = shift;
    my $exons = shift;

    my @results;

    my $remainder = $self->_core_align;

    my $prev_e_end = 0;
    my $e_count = 0;

    while (my $exon_pair = shift @$exons) {

        ++$e_count;

        $self->throw("Ran out of ref sequence for exon $e_count") unless $remainder;

        my ($e_start, $e_end) = @$exon_pair;
        $self->throw("Start of exon $e_count not contiguous with previous end [$prev_e_end:$e_start]")
            unless $e_start == $prev_e_end + 1;

        my $refseq = $remainder->reference_seq->seq;
        my $r_remain = length $refseq;

        my $e_length = $e_end - $e_start + 1;
        my $r_length = $e_length;

        # It might be quicker and easier just to iterate over the string?
        my $last_count = 0;
        while (    ( (my $count = (substr($refseq, 0, $r_length) =~ tr/-//)) > ($r_length - $e_length) )
               and $r_length <= $r_remain ) {
            $r_length += ($count - $last_count);
            $last_count = $count;
        }

        $self->throw("Overran ref sequence for exon $e_count") if $r_length > $r_remain;

        push @results, $remainder->slice(1, $r_length);

        if ($r_length < $r_remain) {
            $remainder = $remainder->slice($r_length + 1, $r_remain);
        } else {
            $remainder = undef;
        }

        $prev_e_end = $e_end;
    }

    $self->warn("Didn't use all of core") if $remainder;

    return \@results;
}

1;

# EOF
