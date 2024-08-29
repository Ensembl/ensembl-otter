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


=head1 NAME - Bio::Otter::Utils::Align

Utilities for displaying EnsEMBL DNA alignment features on a terminal.

=head1 USAGE

    use Bio::Otter::Utils::Align qw(
        print_feature_align
        aligned_sequences
        print_align
    );

We use the EnsEMBL API to create the alignment and pfetch to retrieve
the hit sequences.

(NB: this module is not a class, so do not call its methods with the
-> operator.)

=cut

### Bio::Otter::Utils::Align

package Bio::Otter::Utils::Align;

use strict;
use warnings;
use Carp;

use Exporter;
use base qw( Exporter );
our @EXPORT_OK =
    qw( 
&print_feature_align
&aligned_sequences
&print_align
);

use Bio::EnsEMBL::Pipeline::SeqFetcher;

# parameters
my $wrap_default = 70; # used by print_align, overridden by the '-wrap' option

=head2 print_feature_align

Print the alignment:

    print_feature_align($dna_align_feature);

The output wraps to 70 columns by default.  You can change this with
the -wrap option.

    print_feature_align($dna_align_feature, -wrap => 100);

=cut

sub print_feature_align {
    my ($feature, @options) = @_;
    print_align
        (@{aligned_sequences($feature)}{qw( seq hit )},
         @options);
    return;
}

=head2 aligned_sequences

Return the sequence and hit sequences of a DNA alignment feature, with
'.' characters inserted to align corresponding bases.  The strings are
returned in a hash reference with keys "seq" and "hit".

    my $sequences = aligned_sequences($dna_align_feature);
    printf "Sequence: %s\n", $sequences->{seq};
    printf "Hit:      %s\n", $sequences->{hit};

=cut

sub aligned_sequences {
    my ($feature) = @_;

    my $segments = [ $feature->ungapped_features ];
    next unless @{$segments};

    my $start = $feature->start;
    my $end   = $feature->end;
    my $strand = $feature->strand;
    my $sequence = $feature->slice->subseq($start, $end, $strand);

    my $reversed = $strand == -1;

    my $align = '';
    my $align_end = $start - 1;

    my $hstart = $feature->hstart;
    my $hend   = $feature->hend;
    my $hstrand = $feature->hstrand;
    my $hsequence = fetch($feature->hseqname);
    my $hlength = length($hsequence);

    my $hreversed = $hstrand == -1;
    if ( $hreversed ) {
        $hsequence = reverse $hsequence;
        $hsequence =~ tr/ACGTacgtRYryKMkmBDHVbdhv/TGCAtgcaYRyrMKmkVHDBvhdb/;
        ( $hstart, $hend ) = map {
            $hlength + 1 - $_;
        } $hend, $hstart;
    }

    my $halign = '';
    my $halign_end = $hstart - 1;
    my $hit_in_range = $hstart <= $hlength && $hend <= $hlength;
    croak sprintf
        "Hit boundaries out of range: start = %d, end = %d, length = %d\n"
        , $hstart, $hend, $hlength
        unless $hit_in_range;

    foreach my $segment ( @{$segments} ) {

        my $segment_start  = $segment->start;
        my $segment_end    = $segment->end;
        ( $segment_start, $segment_end ) = map {
            $start + $end - $_;
        } $segment_end, $segment_start,
        if $reversed;

        my $segment_hstart = $segment->hstart;
        my $segment_hend   = $segment->hend;
        ( $segment_hstart, $segment_hend ) = map {
            $hlength + 1 - $_;
        } $segment_hend, $segment_hstart,
        if $hreversed;

        $halign .= '.' x ($segment_start  - ($align_end  + 1));
        $align  .= '.' x ($segment_hstart - ($halign_end + 1));

        $align .= substr
            ($sequence,
             ($align_end + 1) - $start,
             $segment_end - $align_end,
            );
        $align_end = $segment_end;

        $halign .= substr
            ($hsequence,
             $halign_end,
             $segment_hend - $halign_end,
            );
        $halign_end = $segment_hend;
    }

    $align  .= '.' x ($end  - $align_end);
    $halign .= '.' x ($hend - $halign_end);

    return {
        seq => $align,
        hit => $halign,
    };
}

my $fetched = { }; # a cache to prevent repeated fetches

sub fetch {
    my ($id) = @_;
    return $fetched->{$id} ||= fetch_($id);
}

my $fetcher;

sub fetch_ {
    my ($id) = @_;
    $fetcher ||= Bio::EnsEMBL::Pipeline::SeqFetcher->new;
    my $seq = $fetcher->run_pfetch($id);
    croak sprintf "Cannot pfetch '%s'!\n", $id unless $seq;
    return $seq->seq;
}

=head2 print_align

Print two strings as an alignment.

    print_align("AA.GTACCTA", "AACGT.CGTA");

This will croak if the two arguments are not the same length.

The output wraps to 70 columns by default.  You can change this with
the -wrap option.

    print_align("AACGT.CGTA", "AACGT.CGTA", -wrap => 100);

=cut

sub print_align {
    my ($s0, $s1, @options) = @_;
    my $options = { @options };
    my $wrap = $options->{-wrap} || $wrap_default;

    my ( $m ) = match_string($s0, $s1);
    while ( $s0 ) {
        my $ss0 = substr($s0, 0, $wrap, '');
        my $ss1 = substr($s1, 0, $wrap, '');
        my $sm  = substr($m,  0, $wrap, '');
        printf "\n%s\n%s\n%s\n", $ss0, $sm, $ss1;
    }

    return;
}

sub match_string {
    my ($s0, $s1) = @_;
    croak sprintf "%s::%s(): inconsistent lengths (%d != %d)!\n"
        , __PACKAGE__, 'match_string', length($s0), length($s1)
        if length($s0) != length($s1);
    my $match = '';
    $match .=
        match_char(substr($s0,0,1,''), substr($s1,0,1,''))
        while $s0;
    return $match;
}

sub match_char {
    my ($c0, $c1) = @_;
    my $match =
        $c0 =~ /[acgt]/ix
        && lc($c0) eq lc($c1);
    return $match ? '|' : ' ';
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=head1 TO DO:

=over

=item *

Display coordinates in print_align.

=item *

Optionally abbreviate long matches and/or indels.

=back
